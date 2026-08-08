# PXL Accounting Test Book

**Status:** Active validation evidence map
**Authority:** Tier 3 Validation Evidence; executable tests and current database behavior prevail
**Owner / Domain:** Accounting Core
**Applies To:** Accounting, tax, posting, reconciliation, and regression test scenarios
**Read When:** Adding or changing accounting tests, validating a finding, or reconciling test coverage
**Do Not Read For:** AI startup or accounting behavior authority without the accounting rules matrix
**Last Reviewed:** 2026-08-08 after production inventory-costing authority proof; dormant IA-5/ECC remains separate and P5.2 remains authoritative and fully enforced

This file records expected accounting/reporting scenarios that must be executed before a finding can be marked `Retested Passed`.

How to execute deterministic scenarios: start the isolated stack with `supabase db start`, run `npm run test:db:local` for a fresh no-seed migration replay plus all **136 files / 3,261 assertions**, and run `npm run test:canonical` for the atomic canonical rebuild plus the canonical/engine verification set (**30 files / 751 assertions**). Run the lanes in that order: test 073 asserts the zero-company bootstrap, so the regression suite must run on a fresh no-seed schema rather than on top of a canonical seed. `npm test` aliases the full pgTAP regression on the current local schema; use `npm run test:db:focused -- supabase/tests/<file>.sql` only as bounded package evidence. The permanent lane order, prerequisites, success/failure rules, hosted read-only boundary, and complete release gates are authoritative in `docs/PXL/13. Testing and Validation/README.md`. `.github/workflows/ci.yml` publishes separate static, fresh-schema/regression, canonical, protected hosted, and summary results; hosted jobs run only for a manually authorized release-candidate dispatch.

Report-page adoption is governed by `docs/PXL/11. Reports/PXL_STANDARD_REPORT_WORKSPACE.md`. Any report marked production-ready under that standard must have evidence for its accounting purpose, authoritative source data, filters, date basis, posting-state basis, totals, reconciliation target, drilldown/drillback path, export metadata, snapshot requirements where applicable, permissions, known limitations, and performance-sensitive scenarios. Visual conformance alone is not sufficient for accounting, tax, compliance, or reconciliation reports.

The active production-readiness gate is `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_CORE_READINESS.md`. Any item marked **PXL Accounting Core Ready** must have engine-level evidence for posting source locking, lifecycle transitions, JE balance, period locks, numbering, source-to-journal traceability, journal-to-source traceability, reversal/void/cancel behavior, tax-detail posting/counter-rows, cross-company denial, master-data validation, and effective-dated tax-rule resolution where applicable.

`docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` defines the expected accounting behavior and required test scenarios for each transaction type. When a transaction row is added or changed there, this test book must gain matching positive and negative scenarios before the transaction can be marked production-ready.

## CRITICAL-FLOW-001 - Core AR/AP Journey with VAT, CWT, and EWT

Status: Executed Passing (2026-07-02), 41/41 assertions in `supabase/tests/001_critical_flow_test.sql`.

Related findings: PXL-AUD-001 (harness), PXL-AUD-022 and PXL-AUD-023 (defects found and fixed by this scenario's first executions).

Scenario (all documents dated on the run date inside an open 2026 fiscal period):

| Step | Transaction | Amounts | Asserted Accounting Behavior |
| ---- | ----------- | ------- | ---------------------------- |
| 1 | Setup: VAT company, branch, FY2026 periods, 9-account COA, GL posting config, SI/OR/VB/PV number series (legacy UI shape), customer, supplier | - | Creator granted owner membership; legacy-shape number series rows gain `document_code` through the sync trigger. |
| 2 | Sales Invoice save/approve/post | 10,000 net + 1,200 output VAT = 11,200 | `SI-000001` issued; balanced JE: DR AR 11,200, CR revenue 10,000, CR output VAT 1,200; one `output_vat` tax detail row (base 10,000, tax 1,200); posted lines immutable. |
| 3 | Official Receipt post with CWT | cash 10,976 + CWT 224 (2% ATC on 11,200 gross) | Balanced JE: DR cash 10,976, DR CWT receivable 224, CR AR 11,200; SI outstanding = 0; one `cwt_receivable` tax detail row (base 11,200, tax 224). |
| 4 | Vendor Bill save/approve/post | 5,000 net + 600 input VAT = 5,600 | Balanced JE: DR expense 5,000, DR input VAT 600, CR AP 5,600; one `input_vat` tax detail row (base 5,000, tax 600). |
| 5 | Payment Voucher post with EWT | cash 5,500 + EWT 100 (2% ATC on explicit 5,000 net base) | Balanced JE: DR AP 5,600, CR cash 5,500, CR EWT payable 100; VB outstanding = 0; one `ewt_payable` tax detail row (base 5,000, tax 100). |
| 6 | Whole-books invariants | - | All JE lines net to zero; AR and AP control accounts net to zero after their clearing documents. |

Notes:

- The harness runs as superuser with `auth.uid()` simulated through `request.jwt.claims`; SECURITY DEFINER RPC membership/owner checks are exercised, RLS policies are not. Role-based RLS scenarios remain open under PXL-AUD-004/PXL-DA-003.
- First executions of this scenario caught PXL-AUD-022 (number series schema drift breaking `fn_next_document_number`) and PXL-AUD-023 (`fn_post_sales_invoice` referencing non-existent `total_net_amount`), both fixed by 20260702 migrations and now covered by assertions.

## AR-AGING-ASOF-001 - Future Receipt and Credit Memo Exclusion

Status: Executed Passing (2026-07-02) in `supabase/tests/002_ar_aging_asof_test.sql`, including GL AR control reconciliation at both as-of dates.

Related findings: PXL-AUD-011.

Scenario:

| Step | Transaction | Date | Amount | Expected Reporting Behavior |
| ---- | ----------- | ---- | ------ | --------------------------- |
| 1 | Posted Sales Invoice | 2026-01-15 | 10,000.00 | AR aging as of 2026-01-31 shows 10,000.00 open. |
| 2 | Posted Official Receipt | 2026-02-15 | 4,000.00 | AR aging as of 2026-01-31 still shows 10,000.00 open; AR aging as of 2026-02-28 reduces by 4,000.00. |
| 3 | Applied Credit Memo | 2026-02-20 | 1,000.00 | AR aging as of 2026-01-31 still shows 10,000.00 open; AR aging as of 2026-02-28 shows 5,000.00 open. |

Expected accounting behavior:

- No new GL entry is created by running the aging report.
- AR aging must be a report/subledger view of already posted SI, OR, and CM activity.
- Future-dated receipt and credit memo applications must not reduce a prior as-of aging report.
- The scenario can only pass when AR aging, customer ledger, GL AR control, report drilldown, and audit trail evidence reconcile for both as-of dates.

## AP-AGING-ASOF-001 - Future Payment Voucher Exclusion

Status: Executed Passing (2026-07-02) in `supabase/tests/003_ap_aging_asof_test.sql`, including GL AP control reconciliation at both as-of dates.

Related findings: PXL-AUD-012.

Scenario:

| Step | Transaction | Date | Amount | Expected Reporting Behavior |
| ---- | ----------- | ---- | ------ | --------------------------- |
| 1 | Posted Vendor Bill | 2026-01-10 | 12,000.00 | AP aging as of 2026-01-31 shows 12,000.00 open. |
| 2 | Posted Payment Voucher cash portion | 2026-02-10 | 7,000.00 | AP aging as of 2026-01-31 still shows 12,000.00 open. |
| 3 | Posted Payment Voucher EWT portion | 2026-02-10 | 1,000.00 | AP aging as of 2026-02-28 shows 4,000.00 open. |

Expected accounting behavior:

- No new GL entry is created by running the aging report.
- AP aging must be a report/subledger view of already posted VB and PV activity.
- Future-dated payment voucher applications must not reduce a prior as-of aging report.
- The scenario can only pass when AP aging, supplier ledger, GL AP control, report drilldown, and audit trail evidence reconcile for both as-of dates.
- Vendor credit application handling is out of scope for this scenario and remains open under PXL-AUD-019.

## AP-AGING-ASOF-002 - Vendor Credit Application Inclusion

Status: Executed Passing (2026-07-02) in `supabase/tests/003_ap_aging_asof_test.sql`, including GL AP control reconciliation as of 2026-03-31.

Related findings: PXL-AUD-019.

Scenario:

| Step | Transaction | Date | Amount | Expected Reporting Behavior |
| ---- | ----------- | ---- | ------ | --------------------------- |
| 1 | Posted Vendor Bill | 2026-03-05 | 8,000.00 | AP aging shows 8,000.00 open before credit application. |
| 2 | Posted/Applied Vendor Credit | 2026-03-20 | 2,000.00 | AP aging as of 2026-03-31 should show 6,000.00 open after the credit. |

Expected accounting behavior:

- Vendor credit applications should reduce AP aging as of the vendor credit application/posting date.
- Input VAT adjustment and supplier ledger impact should reconcile to the posted vendor credit and GL.
- The scenario can only pass when AP aging, supplier ledger, GL AP control, input VAT adjustment support, report drilldown, and audit trail evidence reconcile.
- Session 8 added scoped UI handling for stored vendor credit applications, but this scenario is not `Retested Passed` until seeded execution validates it.

## ASOF-LEDGER-RECON-001 - Customer/Supplier Ledger and GL Reconciliation

Status: Executed Passing (2026-07-14) in `supabase/tests/051_asof_ledger_reconciliation_test.sql`, 16 assertions.

Related findings: PXL-DA-013.

Scenario:

| Step | Transaction | Date | Amount | Expected Reporting Behavior |
| ---- | ----------- | ---- | ------ | --------------------------- |
| 1 | Posted Sales Invoice | 2026-01-15 | 10,000.00 | Customer ledger as of 2026-01-31 shows only the SI and a 10,000.00 AR balance. |
| 2 | Posted Official Receipt | 2026-02-15 | 4,000.00 | Customer ledger as of 2026-02-19 includes SI + OR only and has a 6,000.00 running balance. |
| 3 | Applied Credit Memo | 2026-02-20 | 1,000.00 | Customer ledger as of 2026-02-28 orders SI, OR, CM and AR subledger-to-GL reconciliation reports a 5,000.00 subledger balance with zero variance. |
| 4 | Posted Vendor Bill | 2026-01-10 | 12,000.00 | Supplier ledger as of 2026-01-31 shows only the VB and a 12,000.00 AP balance. |
| 5 | Posted Payment Voucher | 2026-02-10 | 7,000.00 cash + 1,000.00 EWT | Supplier ledger as of 2026-02-28 has a 4,000.00 running balance. |
| 6 | Posted Vendor Bill and Vendor Credit | 2026-03-05 / 2026-03-20 | 8,000.00 / 2,000.00 | Supplier ledger as of 2026-03-31 orders VB, PV, VB, VC and AP subledger-to-GL reconciliation reports a 10,000.00 subledger balance with zero variance. |

Expected accounting behavior:

- No new GL entry is created by running the ledger or reconciliation reports.
- Customer ledger rows must honor the cutoff date and include only AR-clearing receipt applications, not customer advances.
- Supplier ledger rows must honor the cutoff date, exclude supplier down-payment rows from AP, and net source-accrued EWT from the originating vendor bill's AP amount.
- Reconciliation reports must use `company_accounting_config.ar_account_id` / `ap_account_id` and compare the as-of subledger totals to posted GL control-account balances.

## VC-APPLICATION-DATE-001 - User-Controlled Vendor Credit Application Date

Status: Executed Passing (2026-07-02) in `supabase/tests/004_vendor_credit_application_controls_test.sql`, including pre-credit-date and locked-period rejection and direct-insert denial.

Related findings: PXL-AUD-020.

Scenario:

| Step | Transaction | Date | Amount | Expected Reporting Behavior |
| ---- | ----------- | ---- | ------ | --------------------------- |
| 1 | Posted Vendor Bill | 2026-04-05 | 9,000.00 | AP aging shows 9,000.00 open before credit application. |
| 2 | Posted Vendor Credit | 2026-04-10 | 3,000.00 | Vendor credit is available for application. |
| 3 | Apply Vendor Credit | 2026-04-15 | 3,000.00 | AP aging as of 2026-04-14 shows 9,000.00 open; AP aging as of 2026-04-30 shows 6,000.00 open. |

Expected accounting behavior:

- The vendor credit application UI should collect and pass the intended application date.
- The application date should be validated against the company's open fiscal periods by both UI and RPC.
- AP aging should use the stored `vendor_credit_applications.applied_date`, not the system date when the user happened to click Apply.
- Sessions 9-10 added scoped UI and RPC handling for application date; this scenario is not `Retested Passed` until seeded execution validates AP aging, supplier ledger, GL/AP control expectations, and audit trail evidence.

## VC-APPLICATION-REVERSAL-001 - Controlled Vendor Credit Application Reversal

Status: Executed Passing (2026-07-02) in `supabase/tests/004_vendor_credit_application_controls_test.sql`, including balance/status restoration, preserved reversal evidence, and direct-delete denial.

Related findings: PXL-AUD-021.

Scenario:

| Step | Transaction | Date | Amount | Expected Reporting Behavior |
| ---- | ----------- | ---- | ------ | --------------------------- |
| 1 | Posted Vendor Credit | 2026-05-10 | 2,500.00 | Vendor credit is open and available. |
| 2 | Apply Vendor Credit to Posted Vendor Bill | 2026-05-12 | 2,500.00 | AP aging reduces the vendor bill balance and vendor credit remaining balance becomes 0.00. |
| 3 | Reverse Application Through Controlled Workflow | 2026-05-15 | 2,500.00 | AP aging restores the bill balance, vendor credit remaining balance returns to 2,500.00, and reversal evidence is retained. |

Expected accounting behavior:

- Direct deletes of application rows should not be allowed.
- A reversal RPC should restore vendor credit balance/status and preserve an audit trail.
- AP aging and supplier ledger should reflect the reversal as of the reversal date.

## NON-VAT-GATING-001 - VAT Registration Enforcement for Non-VAT Companies

Status: Executed Passing (2026-07-02) in `supabase/tests/005_non_vat_registration_gating_test.sql`.

Related findings: PXL-AUD-006, PXL-AUD-014.

Scenario (non-VAT sole proprietor company):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save SI line with VAT-12 output code | Rejected: non-VAT/exempt companies cannot use VAT-bearing codes. |
| 2 | Save/approve/post SI with VAT-EXEMPT code for 10,000.00 | Posts with zero output VAT and no output VAT tax detail row. |
| 3 | Save VB line with IVAT-12 input code | Rejected: non-VAT/exempt companies cannot use VAT-bearing codes. |
| 4 | Save/approve/post VB with IVAT-EXEMPT code for 5,000.00 | Posts with zero input VAT. |
| 5 | Insert a 2550M `vat_returns` row for the company | Rejected: VAT return requires a VAT-registered company. |

Remaining under the related findings: VAT tax-ledger-to-GL reconciliation and filed/exported return provenance.

## PV-EWT-PARTIAL-001 - EWT on Partial Payments with Explicit Basis

Status: Executed Passing (2026-07-02; re-executed session 83, 2026-07-13) in `supabase/tests/006_pv_ewt_partial_payment_test.sql`.

Related findings: PXL-AUD-007, PXL-DA-009, PXL-DA-010.

Scenario (VAT company explicitly using the `payment` AP EWT recognition policy; VB 2026-01-10 for 11,200.00 = 10,000.00 net + 1,200.00 input VAT):

| Step | Transaction | Date | Amounts | Expected Behavior |
| ---- | ----------- | ---- | ------- | ----------------- |
| 1 | PV 1 (half) | 2026-02-05 | cash 5,500.00 + EWT 100.00 (2% ATC on explicit 5,000.00 base) | Posts; bill outstanding 5,600.00; one ewt_payable tax detail row (base 5,000.00, tax 100.00). |
| 2 | PV 2 (half) | 2026-03-05 | cash 5,500.00 + EWT 100.00 | Posts; bill fully settled; cumulative EWT 200.00 on cumulative base 10,000.00; EWT payable GL account accumulates 200.00. |
| 3 | PV 3 attempt | 2026-04-05 | 100.00 | Rejected: exceeds outstanding AP balance. |
| 4 | EWT 150.00 on 5,000.00 base at 2% without variance reason | - | Rejected: amount does not match the ATC rate. |
| 5 | Same variance with reason `other_authorized` | - | Accepted; unrecognized reason strings rejected. |
| 6 | EWT against an ATC whose `effective_to` has passed | - | Rejected: inactive, expired, or deprecated ATC. |

## F2307-ISSUED-001 - Server-Side 2307 Generation, Regeneration, and Status Locks

Status: Executed Passing (2026-07-02) in `supabase/tests/007_form2307_issued_generation_test.sql`.

Related findings: PXL-AUD-015.

Scenario (posted PV EWT detail from PV-EWT-PARTIAL-style flow, both vouchers in Q1 2026):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Generate Q1 2026 via `fn_generate_form_2307_issued` after the first PV | One certificate in `generated` status; total EWT 100.00; one ATC-level line with code, income nature, explicit base 5,000.00, rate 2%, withheld 100.00. |
| 2 | Post a second Q1 PV and regenerate | Same certificate refreshed: total EWT 200.00 on base 10,000.00; lines replaced, not duplicated. |
| 3 | Mark sent via `fn_update_form_2307_issued_status` | Status becomes `sent` with a recorded date. |
| 4 | Regenerate again | Sent certificate is locked: status and totals unchanged. |
| 5 | Direct UPDATE of the issuance or INSERT of a line as an authenticated user | Denied (42501); writes only through the RPCs. |

The certificate version/supersede workflow is covered by F2307-SUPERSEDE-001 below.

## F2307-SUPERSEDE-001 - Certificate Version/Supersede Workflow

Status: Executed Passing (2026-07-03) in `supabase/tests/010_form2307_supersede_test.sql`.

Related findings: PXL-AUD-015, PXL-DA-015.

Scenario (VB 11,200 in Q1 2026; PV1 2026-02-05 withholds 100.00 on base 5,000.00; certificate generated and marked sent; PV2 2026-03-05 withholds another 100.00):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Mark generated v1 sent | Creates one `report_snapshots` row with report type `FORM_2307_ISSUED`, status `sent`, version 1, Q1 period bounds, one certificate line, and a 64-character SHA-256 source hash over the certificate header, certificate lines, and EWT source rows. |
| 2 | Try changing v1 total EWT after the sent snapshot exists | Rejected because certificate amount and identity fields are immutable after a sent/acknowledged snapshot. |
| 3 | Regenerate the quarter after the late PV | Sent certificate stays locked at 100.00. |
| 4 | `fn_supersede_form_2307_issued` on the sent certificate with a reason | New version 2 in `generated` status with refreshed totals (200.00 withheld on 10,000.00) and one refreshed ATC line; old certificate becomes `superseded` with `superseded_at` and a two-way link; its original lines survive as evidence. |
| 5 | Count active certificates for the supplier/quarter | Exactly one (partial unique index on non-superseded certificates). |
| 6 | Regenerate the quarter again | Only the active version refreshes; the superseded certificate is never resurrected or altered. |
| 7 | Supersede the generated v2, or the superseded v1 | Both rejected: only sent/acknowledged certificates can be superseded. |
| 8 | Mark replacement v2 sent | Creates a separate `report_snapshots` row for version 2 with status `sent`, Q1 period bounds, one certificate line, and a 64-character SHA-256 source hash. |
| 9 | Direct `UPDATE` to un-supersede as an authenticated user | Denied by RLS/effectively matches no row. |

## F2307-MONTHLY-001 - Form 2307 Month-of-Quarter Breakdown

Status: Executed Passing (2026-07-14, session 90) in `supabase/tests/044_form2307_monthly_breakdown_test.sql` with 8 assertions.

Related findings: PXL-AUD-040, PXL-AUD-015, PXL-DA-015.

Scenario (supplier EWT source rows in January, February, and March 2026; certificate generated for Q1):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Generate Q1 2026 via `fn_generate_form_2307_issued` | Certificate totals equal the source quarter, and the line retains separate month-1/month-2/month-3 base and withheld amounts. |
| 2 | Mark the certificate sent | `fn_snapshot_form2307_issued` freezes the monthly certificate-line payload in `report_snapshots.snapshot_data`. |
| 3 | Add a late March withholding row and supersede the sent certificate | Old version keeps its original month-3 evidence; replacement version refreshes the quarter total and month-3 bucket. |
| 4 | Compare old and new evidence | Month-1/month-2 values remain stable, while replacement month-3 base/withheld includes the late row. |

## WHT-MASTER-CONSOLIDATION-001 - Withholding Master Consolidation

Status: Executed Passing (2026-07-14, session 91) in `supabase/tests/045_withholding_master_consolidation_test.sql` with 12 assertions.

Related findings: PXL-AUD-044.

Scenario (final schema after retiring duplicate customer flags and unused EWT/FWT wrapper masters):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect the schema for retired wrapper structures | `ewt_codes` and `fwt_codes` no longer exist. |
| 2 | Inspect customer, supplier, and item columns | `customers.is_withholding_agent`, `customers.default_ewt_code_id`, `suppliers.default_ewt_code_id`, and `items.default_ewt_code_id` no longer exist. |
| 3 | Create a customer with `default_cwt_atc_code_id` but `is_subject_to_cwt = false` | The existing CWT default trigger auto-enables `is_subject_to_cwt`, proving the single customer CWT flag/default path remains operative. |
| 4 | Call `fn_atc_code_used` for the customer default ATC | Returns true without relying on the retired wrapper tables. |
| 5 | Create a supplier with `default_atc_code_id` but `is_subject_to_ewt = false` | The existing supplier default trigger auto-enables `is_subject_to_ewt`, proving AP defaults point directly at ATC masters. |
| 6 | Call `fn_atc_code_used` for the supplier default ATC | Returns true through `suppliers.default_atc_code_id`, so used ATCs remain protected after wrapper retirement. |

## WHT-MASTER-DEFAULTS-001 - Supplier/Customer Withholding Default Flows

Status: Executed Passing (2026-07-14, session 95) in `supabase/tests/049_withholding_master_defaults_test.sql` with 15 assertions.

Related findings: PXL-AUD-008.

Scenario (single ATC-backed supplier/customer withholding defaults after master consolidation):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Create supplier/customer defaults with FWT ATC WC001 | Both writes are rejected because supplier EWT and customer CWT defaults must reference active/current withholding ATCs for the expected side. |
| 2 | Create supplier and customer with WC140 defaults while their withholding flags are false | The database auto-enables `is_subject_to_ewt` / `is_subject_to_cwt` and stores the ATC-backed defaults. |
| 3 | Save/post a source-basis VAT vendor bill for the supplier | The VB line derives ATC WC140, base 10,000.00, EWT 200.00; the header expected EWT matches; posting writes supplier-linked `ewt_payable` tax detail. |
| 4 | Generate issued Form 2307 for Q1 | The certificate line preserves WC140, base 10,000.00, withheld 200.00, and month-1 withheld 200.00. |
| 5 | Save/post a VAT sales invoice and receipt for the customer | The receipt line uses the customer default WC140 on explicit base 10,000.00 with CWT 200.00; posting writes customer-linked `cwt_receivable` tax detail. |
| 6 | Record received Form 2307 evidence against the receipt line | The governed RPC creates received evidence for 200.00 under WC140, making the customer-default CWT claimable through the received-certificate lifecycle. |

## ACCOUNTING-READINESS-APPROVAL-001 - SI/VB Approval Readiness and EWT Identity

Status: Executed Passing (2026-07-14, session 96) in `supabase/tests/050_accounting_readiness_approval_test.sql` with 17 assertions.

Related findings: PXL-AUD-009, PXL-AUD-010.

Scenario: a VAT company exercises both approval RPCs and direct status-transition triggers for sales invoices and vendor bills, plus AP-side EWT supplier-TIN readiness.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save a draft SI line with no revenue account, then approve via RPC | Rejected: every SI line must have a revenue account before approval/posting. |
| 2 | Directly update the same SI to `approved` | Rejected by the database status trigger with the same revenue-account readiness error. |
| 3 | Save an SI using an inactive revenue account | Approval is rejected because the revenue account is not active/postable for the company. |
| 4 | Save an SI with VAT-12 while active, deactivate the VAT code, then approve | Approval is rejected because the output VAT code is no longer active/valid. |
| 5 | Save, approve, and post an accounting-ready SI | Approval and posting both succeed, and the SI ends `posted`. |
| 6 | Save a draft VB line with no expense account, then approve via RPC | Rejected: every VB line must have an expense account before approval/posting. |
| 7 | Directly update the same VB to `approved` | Rejected by the database status trigger with the same expense-account readiness error. |
| 8 | Save a VB using an inactive expense account | Approval is rejected because the expense account is not active/postable for the company. |
| 9 | Save a VB with IVAT-12 while active, deactivate the VAT code, then approve | Approval is rejected because the input VAT code is no longer active/valid. |
| 10 | Save, approve, and post an accounting-ready VB | Approval and posting both succeed, and the VB ends `posted`. |
| 11 | Save a source-basis EWT VB whose supplier master and header snapshot both have blank TIN | RPC approval and direct approved-status transition are both rejected before posting. |
| 12 | Save a supplier down-payment PV with EWT and no usable supplier TIN snapshot | PV posting is rejected before an EWT tax-detail row can be written. |

## VAT-RECON-001 - VAT Tax-Ledger-to-GL Reconciliation and Return Gate

Status: Executed Passing (2026-07-03) in `supabase/tests/008_vat_ledger_gl_reconciliation_test.sql`.

Related findings: PXL-AUD-014, PXL-DA-008, PXL-DA-015.

Scenario (VAT company; SI 2026-01-15 for 10,000.00 + 1,200.00 output VAT; VB 2026-01-20 for 5,000.00 + 600.00 input VAT):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Run `fn_vat_gl_reconciliation` for January | Output VAT: ledger 1,200.00 = GL control 1,200.00; input VAT: ledger 600.00 = GL control 600.00; variance 0, reconciled. |
| 2 | Save January 2550M draft with matching figures, then mark final | Both allowed; marking final creates one `report_snapshots` row with a 64-character SHA-256 source hash over the return payload, VAT review source rows, and VAT/GL reconciliation rows. |
| 3 | Try changing the final return's output VAT | Rejected because a snapshot exists; amount and period identity fields are immutable after final/filed snapshot creation. |
| 4 | Mark the January return filed with filed date and reference number | Allowed; filing metadata update creates a separate `filed` snapshot without altering the `final` snapshot. |
| 5 | Export January SLSP sales and purchases | Each export creates a `report_snapshots` row with status `exported`, version 1, export part (`sales` or `purchases`), one source row, and a 64-character SHA-256 source hash. |
| 6 | Export January RELIEF for all rows twice | First export creates an `exported` snapshot with two source detail rows; second export creates version 2 for the same company/report/month/part. |
| 7 | Save a final 2550M whose output VAT (999.00) diverges from the tax ledger | Rejected: return figures must match the tax ledger. |
| 8 | Post a manual JE crediting the output VAT control account 500.00 with no tax detail (2026-02-10) | Posts; February reconciliation shows ledger 0.00 vs GL 500.00, variance -500.00, not reconciled. |
| 9 | Save February 2550M draft | Allowed: drafts are never blocked by reconciliation. |
| 10 | Mark the February return final, then filed | Both rejected while the period tax ledger does not reconcile to the GL control account. |
| 11 | Export February RELIEF | Rejected while the period tax ledger does not reconcile to the GL control account. |

Notes:

- Reconciliation uses `tax_detail_entries.document_date` (accounting date aligned with `je_date`); `posting_date` stores the system date at posting time (logged as PXL-AUD-025).
- GL amounts use `je.status = 'posted'` to match `vw_general_ledger`/`vw_trial_balance`; the JE reversal double-count defect in those views is logged as PXL-AUD-024.
- VAT return final/filed snapshots, Form 2307 issued sent/acknowledged snapshots, and SLSP/RELIEF exported snapshots are the first PXL-DA-015 slices. Remaining provenance work: apply the same snapshot/export model to SAWT, QAP, books, and CAS exports.

## GL-REVERSAL-001 - JE Reversal Nets to Zero in GL and Trial Balance

Status: Executed Passing (2026-07-02) in `supabase/tests/009_gl_reversal_visibility_test.sql`.

Related findings: PXL-AUD-024.

Scenario (manual JEs on a minimal VAT company):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Post manual JE 2026-03-10: DR Office Expense 1,000.00, CR Cash 1,000.00 | GL shows the expense debit of 1,000.00. |
| 2 | Reverse via `fn_reverse_je` dated 2026-03-15 | GL shows both the reversed original and the posted counter-entry; the expense account nets to 0.00 in `vw_general_ledger` and `vw_trial_balance`; the whole GL still nets to zero. Before `20260702000005` the account showed -1,000.00 (reversal applied twice). |
| 3 | Post manual JE 2026-04-10 crediting the output VAT control account 500.00 without tax detail | `fn_vat_gl_reconciliation` shows a -500.00 April variance. |
| 4 | Reverse that JE dated 2026-04-20 (same period) | April VAT reconciliation returns to GL 0.00, variance 0.00, reconciled. |

Notes:

- Convention: both the original (`reversed`) and its counter-JE (`posted`) stay visible in report views; drafts stay excluded. Every reversal/void path was verified to post a counter-JE before this convention was adopted.
- Period-crossing reversals net to zero only across the two periods combined — each period correctly retains its own activity.

## RLS-ROLES-001 - Role-Based Access Controls

Status: Executed Passing (2026-07-02) in `supabase/tests/011_role_based_access_test.sql`.

Related findings: PXL-AUD-004, PXL-DA-003, PXL-AUD-026.

Scenario (company A with owner, admin, member, and viewer memberships; an outsider owns company B; every assertion runs as the `authenticated` role with per-user JWT claims — the first seeded test to exercise RLS itself rather than running as superuser):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Outsider queries company A and its customers | Zero rows through RLS: cross-company isolation. |
| 2 | Member and viewer read company A branches | Allowed. |
| 3 | Member and viewer insert a branch | Rejected (42501): setup writes require owner/admin. |
| 4 | Admin inserts a branch | Allowed. |
| 5 | Member updates `fiscal_periods.is_locked` | Silently matches no rows under RLS; no period becomes locked. |
| 6 | Member inserts a number series | Rejected (42501). |
| 7 | Member saves a draft SI via `fn_save_sales_invoice` | Allowed: members may enter drafts. |
| 8 | Member approves the accounting-ready SI | Rejected by the `fn_can_perform` lifecycle gate: approval requires owner/admin (DEC-009). |
| 9 | Admin approves the accounting-ready SI | Approved. |
| 10 | Member posts the SI | Rejected by the lifecycle trigger: restricted status transitions require owner/admin. |
| 11 | Admin posts the SI | Posted. |
| 12 | Outsider calls `fn_save_sales_invoice` against company A | Rejected: Access denied. |

Notes:

- The first `SET ROLE authenticated` query in this scenario exposed PXL-AUD-026: the migration chain never granted table privileges to `authenticated`, so a migrations-only database rejects every PostgREST query. Fixed by `20260702000008_authenticated_table_grants.sql`; RLS was verified enabled on all public tables before granting, and `anon` receives no grants.
- With grants restored, `UPDATE`/`DELETE` policies with `USING (false)` silently match no rows instead of raising 42501, while `INSERT` `WITH CHECK` violations still raise 42501. The direct-write denial assertions in tests 004/007/010 were rewritten as effect-based checks (row survives / row unchanged) accordingly.
- `fn_can_perform` (DEC-009) now backs the lifecycle gate, so approval joined the owner/admin-only statuses; the role/action matrix itself is exercised by RBAC-CANPERFORM-001. Approver-not-creator segregation when a workflow is configured remains open under PXL-DA-012.

## TAX-LEDGER-VOID-001 - Void/Cancel/Bounce Tax Ledger Counter-Entries

Status: Executed Passing (2026-07-02) in `supabase/tests/012_tax_ledger_void_reversal_test.sql`.

Related findings: PXL-AUD-027 (discovered tracing PXL-AUD-014/PXL-DA-008).

Scenario (VAT company; January SI 10,000 + 1,200 output VAT and VB 5,000 + 600 input VAT; both voided today; February SI collected by an OR with 224 CWT that then bounces; March VB paid by a PV with 100 EWT that is then cancelled):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Reconcile January before any void | Output 1,200 and input 600 reconcile, variance 0. |
| 2 | Void the posted SI | Original `output_vat` row preserved untouched (`is_reversal = false`, amounts intact); a counter-row of -10,000/-1,200 exists, `is_reversal = true`, linked via `reverses_tax_detail_id`, `document_date` = void date. |
| 3 | Re-reconcile January and the void month | January still reconciles at 1,200 = 1,200; the void month reconciles at -1,200 ledger = -1,200 GL (counter-row matches the reversal JE period), variance 0 in both. |
| 4 | Void the posted VB | No original row is flag-flipped (old mutation behavior gone); a -5,000/-600 counter-row exists; full-year VAT nets to zero and reconciles for both kinds. |
| 5 | Post OR with 224 CWT, then bounce it | CWT receivable for the OR nets to zero; the counter-row is linked and dated on the bounce date. |
| 6 | Post PV with 100 EWT, then cancel it | PV disappears from `vw_ewt_summary_ap` (2307 source data) entirely, while the raw ledger preserves both rows netting to zero. |
| 7 | Void the SI again | Rejected: already voided. |
| 8 | Final full-year reconciliation | Only live activity remains (SI2 1,200 output, VB2 600 input), reconciled. |

Notes:

- Counter-rows are dated on the reversal date, matching the reversal JE, so each period retains its own activity — the same convention GL-REVERSAL-001 proves for the GL views.
- `is_reversal = true` now uniformly marks negative/corrective rows only (CM reversals and void/cancel/bounce counters); reversed originals are identified by an incoming `reverses_tax_detail_id` link, never by mutation.
- The migration backfills existing environments: previously flag-flipped VB rows are restored and missing counter-rows are inserted for already-voided/cancelled/bounced documents, dated at their reversal JE.

## RBAC-CANPERFORM-001 - fn_can_perform Role/Action Matrix

Status: Executed Passing (2026-07-03) in `supabase/tests/013_can_perform_test.sql`.

Related findings: PXL-DA-003, PXL-AUD-004. Decision: DEC-009.

Scenario (company A with owner, admin, member, and viewer memberships plus a non-member; all assertions run as the `authenticated` role with per-user JWT claims):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Owner calls `fn_can_perform(company, 'post', 'sales_invoices')` | TRUE: owner/admin hold every action. |
| 2 | Member checks `post` and `approve` | FALSE for both: capture-only authority. |
| 3 | Member checks `master_data` | TRUE: members maintain operational master data. |
| 4 | Viewer checks `master_data` | FALSE: read-only. |
| 5 | Non-member checks `create` | FALSE: no membership, no authority. |
| 6 | Member inserts a customer and edits an existing one | Allowed by the `fn_can_perform`-backed RLS policies. |
| 7 | Member inserts a supplier | Allowed. |
| 8 | Viewer inserts a customer | Rejected (42501). |
| 9 | Viewer updates a customer | Silently matches no rows under RLS; name unchanged. |
| 10 | Member deletes a customer | Silently matches no rows: master-data delete stays owner/admin. |
| 11 | Admin deletes the customer | Deleted. |

Notes:

- `fn_can_perform(company_id, action, document_type)` is the DEC-009 matrix on the existing owner/admin/member/viewer roles; `document_type` is recorded for future per-document-type refinement (accountant/bookkeeper mappings) and not yet consulted.
- The lifecycle trigger `fn_require_admin_for_accounting_lifecycle` now routes through `fn_can_perform`, and `approved` joined the default restricted-status list, closing the member-approval hole (see RLS-ROLES-001 step 8).
- Migration `20260702000010_can_perform_role_actions.sql` also added previously missing lifecycle gates: petty cash voucher approval and `journal_entries` insert/status paths.
- Items share the identical policy expression as customers/suppliers; the item insert path is not re-tested because its prerequisites (category/UoM) are admin-only setup.

## APPROVAL-SOD-001 - Approval Segregation of Duties

Status: Executed Passing (2026-07-03) in `supabase/tests/014_approval_sod_test.sql`.

Related findings: PXL-DA-012. Decision: DEC-010.

Scenario (company with owner, admin, and member; workflow W1 governs all `sales` documents `always`; workflow W2 governs Vendor Bills above 10,000; all assertions run as the `authenticated` role):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Match W1 for a Sales Invoice and an Official Receipt | Blank document type on a workflow covers every document of its module. |
| 2 | Match W2 for a 5,000 vendor bill | NULL: below the `amount_exceeds` threshold, no approval required. |
| 3 | Match W2 for a 15,000 vendor bill | W2 returned: approval required above the threshold. |
| 4 | Member inserts an approval workflow | Rejected (42501): approval setup stays owner/admin. |
| 5 | Owner (creator) approves their own SI via RPC | Rejected: "segregation of duties" — creator cannot approve. |
| 6 | Admin approves the SI | Approved; an `approval_instances` row records workflow, actor, and timestamp. |
| 7 | Owner (creator) posts the approved SI | Allowed: the approver differed from the creator, so the creator may post. |
| 8 | Owner directly UPDATEs a second SI to `approved` | Rejected at the RPC-only table boundary; the approval RPC separately enforces approver-not-creator. |
| 9 | Post with no instance and legacy `approved_by` = creator | Rejected: no qualifying approval. |
| 10 | Post with legacy `approved_by` = a different admin | Allowed: pre-migration approvals qualify when the approver differed. |
| 11 | Deactivate W1, owner approves their own new SI | Allowed: no active workflow means only the DEC-009 role gate applies. |

Notes:

- Enforcement lives in `fn_enforce_approval_sod` BEFORE triggers on sales_invoices, vendor_bills, receipts, payment_vouchers, purchase_orders, and petty_cash_vouchers (`20260703000001_approval_sod_enforcement.sql`); `fn_required_approval_workflow` resolves the governing workflow (specific document type beats blank; `amount_exceeds` compares the document total; other trigger conditions are conservatively treated as always-required until evaluators exist).
- Receipts and payment vouchers post directly from draft, so for them posting is the approval act: the creator cannot post when a workflow is configured, and the posting is recorded as the approval instance.
- `journal_entries` is not gated: system JEs from posting RPCs are indistinguishable from manual JEs, so a `journal` workflow would block every posting path. Multi-step workflows record the first step only. Approval invalidation on post-approval edits is tracked under PXL-AUD-005/PXL-DA-011.

## VAT-LEDGER-COMPLETE-001 - Per-VAT-Code Tax Ledger Completeness

Status: Executed Passing (2026-07-03) in `supabase/tests/015_vat_ledger_completeness_test.sql`.

Related findings: PXL-AUD-014, PXL-DA-008; discovered and fixed PXL-AUD-028 (cash sale runtime-dead defects) on first execution.

Scenario (VAT company; seeded VAT codes VAT-12/VAT-0-EXPORT/VAT-EXEMPT and IVAT-12/IVAT-0; WC140 2% ATC):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Post an SI with regular 10,000, zero-rated 5,000, and exempt 3,000 lines | Three output VAT ledger rows, one per VAT code: 10,000/1,200, 5,000/0, 3,000/0. |
| 2 | Post an all-exempt SI (2,000) | One ledger row with base 2,000 and zero tax — previously zero-VAT documents left no evidence. |
| 3 | Post a VB with regular 4,000 and zero-rated 1,500 lines | Two input VAT rows: 4,000/480 and 1,500/0. |
| 4 | Cash sale: VAT-12 1,000 + exempt 500 lines, CWT 32.40 under WC140 | SI header stores taxable 1,000 / exempt 500 / VAT 120; two per-code output rows; OR writes a `cwt_receivable` row (base 1,620 = payment + CWT, rate 2%). |
| 5 | Post a cash purchase with a regular 2,000 line | One input VAT row 2,000/240 — previously cash purchases wrote nothing. |
| 6 | Read March output VAT review / 2550 source totals | `vw_output_vat_review` is ledger-backed: gross 22,820, taxable 11,000, zero-rated 5,000, exempt 5,500, output VAT 1,320; the cash-sale row is identified from the linked SI. |
| 7 | Read March input VAT review / 2550 source totals | `vw_input_vat_review` is ledger-backed: gross 8,220, taxable 6,000, zero-rated 1,500, exempt 0, input VAT 720, including the cash purchase. |
| 8 | Reconcile March | Output 1,320 = GL 1,320; input 720 = GL 720; zero-amount classification rows do not disturb the control. |
| 9 | Void the mixed SI | Three counter-rows, one per VAT code, each linked via `reverses_tax_detail_id`; every code nets to zero base and tax; unrelated evidence untouched; the output VAT review exposes the reversal rows in the reversal period from `tax_detail_entries`. |

Notes:

- Writers are gated on `companies.tax_registration = 'vat'` and line-level `vat_code_id`; non-VAT companies keep writing nothing (NON-VAT-GATING-001 asserts this).
- Legacy lump rows (NULL `vat_code_id`) remain untouched; ledger consumers must treat NULL as regular. The migration backfills missing per-code rows for posted documents only, so void netting from TAX-LEDGER-VOID-001 stays exact.
- `vw_output_vat_review` and `vw_input_vat_review` now aggregate from `tax_detail_entries`; the 2550M/2550Q pages already consume those views, so their generated figures inherit the same ledger-backed source.
- First execution of `fn_save_cash_sale` exposed PXL-AUD-028 (phantom columns, zero totals from UI payloads, AR over-application, missing ATC); the function now recomputes amounts server-side like `fn_save_sales_invoice`, and `CashSalesPage` collects the CWT ATC.

## WHT-EXPORT-SNAP-001 — RETIRED 2026-08-04 with Backlog 8f

Status: **Retired.** The test file `016_wht_export_snapshots_test.sql` was
deleted when its subject was: `fn_snapshot_wht_export` and `wht_export_periods`
were removed by migration `20260804000006`. The SAWT and QAP screens export
through `fn_snapshot_filing_artifact_export`, which is keyed to the artifact's
own id rather than to a synthesised export-period key, so the legacy path had no
consumer left but this file.

Two of its claims were **not** about that subject and were migrated rather than
dropped, into `129_compliance_architecture_verification_test.sql`: report
snapshots are append-only to an ordinary user (129.13), and an export is refused
while the control account no longer reconciles (129.14) — asserted there against
a *final* artifact whose account mapping has since moved, which is the
misconfiguration the guarantee exists for. Snapshot versioning and hashing are
covered by `126` (assertions 21, 23). Nothing this file proved is now unproven.

## CAS-EXPORT-SNAP-001 - CAS DAT Export Snapshots and Server-Attested Export Log

Status: Executed Passing (updated 2026-07-13) in `supabase/tests/017_cas_export_snapshots_test.sql` (29 assertions).

Related findings: PXL-DA-015 (report provenance, fifth slice), PXL-DA-019 (DAT layout/exported-byte evidence slice).

Scenario (VAT company; February 2026 books: SI 10,000 + 1,200 output VAT, OR with 224.00 CWT, VB 5,000 + 600 input VAT, PV with 100.00 EWT):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Generate the SLSP DAT extract | `fn_snapshot_cas_export` creates an `exported` v1 `CAS_SLSP` snapshot (period 2026-02-01..2026-02-28, 64-character source SHA-256 hash) and writes the `cas_export_log` row itself: server-attested row count, `generated_by`, `snapshot_id`, `artifact_id`, layout version, file SHA-256, and UTF-8 byte size. |
| 2 | Compare the RPC response to the snapshot and DAT artifact | The rows returned to the caller are exactly the frozen `export_rows`; the CRLF-delimited `PXL-CAS-DAT-1.0` `export_text` returned for download is exactly `source_payload.export_file_text`; `source_payload.export_file_sha256` equals SHA-256 over those exact UTF-8 bytes; `fn_render_cas_dat` returns the same immutable artifact and is idempotent. |
| 3 | Generate RELIEF and alphalist extracts | Separate `CAS_RELIEF` / `CAS_QAP` snapshots freeze both sales and purchases RELIEF rows, including BIR counterparty/VAT classification fields, and the PV EWT row (100.00). |
| 4 | Generate the GL extract | `CAS_GL` snapshot freezes every GL line of the period and records the debit=credit balance check in its reconciliation payload; returned `row_count` matches the returned rows. |
| 5 | Re-generate SLSP for the same month | v2 on the same deterministic logical source — export history is versioned, never overwritten. |
| 6 | Attempt a direct `cas_export_log` insert as `authenticated` | Rejected (42501): the log is RPC-only evidence. |
| 7 | Request an unknown report type or blank file name | Rejected with explicit errors. |
| 8 | Post a manual JE crediting the output VAT control, then re-export | SLSP extract is blocked (`does not reconcile`); alphalist and GL extracts still succeed — gates are per-report. |

Notes:

- The page previously assembled CSVs in the browser and inserted its own `cas_export_log` rows (client-computed row counts, no hash). `CASDATFileGenerationPage` now downloads `.dat` files using the exact CRLF `PXL-CAS-DAT-1.0` text rendered by the RPC, frozen in the snapshot payload, and mirrored into `cas_export_artifacts`.
- DA-019 is closed for the current CAS evidence scope: DAT byte layout, exact exported bytes, books source/GL reconciliation, and audit-package snapshots are all covered by tests 017/018.

## BOOKS-EXPORT-SNAP-001 - BIR Books of Accounts Export Snapshots

Status: Executed Passing (updated 2026-07-13) in `supabase/tests/018_books_export_snapshots_test.sql` (22 assertions).

Related findings: PXL-DA-015 (report provenance, sixth slice), PXL-DA-019 (exported-byte, reconciliation, and audit-package evidence slices).

Scenario (VAT company; February 2026 books: SI 11,200 gross, OR with 224.00 CWT, VB 5,600 gross, PV net 5,400 after 100.00 EWT):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Export the sales journal for Feb 1-28 | `fn_snapshot_books_export` creates an `exported` v1 `BOOKS_SALES_JOURNAL` snapshot (64-character source SHA-256 hash) and writes the `cas_export_log` row itself (`csv_export`, server row count, range in remarks, `snapshot_id`, file SHA-256, byte size). |
| 2 | Compare the RPC response to the snapshot | Returned rows are exactly the frozen `export_rows`; returned `export_text` is exactly `source_payload.export_file_text`, and `source_payload.export_file_sha256` equals SHA-256 over those exact UTF-8 bytes. |
| 3 | Inspect sales-journal reconciliation | Snapshot stores source-to-export reconciliation and linked balanced GL evidence: exported rows/total match posted SI rows, linked journal entries are complete, and linked GL debits equal credits. |
| 4 | Export the purchase journal | Freezes the VB with its gross total (5,600.00) in the integrity payload. |
| 5 | Export the cash receipts book | Freezes the OR collection gross of CWT (11,200.00), doc type `OR`. |
| 6 | Export the cash disbursements book | Freezes the PV payment net of EWT (5,400.00), doc type `PV`. |
| 7 | Inspect source-book reconciliation | Purchase, cash receipts, and cash disbursements snapshots each store reconciled posted source rows, zero missing journal entries, and linked balanced GL evidence. |
| 8 | Export the general journal | Freezes every GL line of the range and records the debit=credit balance check; an unbalanced range would be blocked. |
| 9 | Export the (empty) cash sales journal | Zero rows still produce hashed snapshot evidence and passing empty-book reconciliation. |
| 10 | Re-export the sales journal for the same range | v2 on the same deterministic logical source. |
| 11 | Generate the CAS audit support package | `fn_snapshot_cas_audit_package` creates a `CAS_AUDIT_PACKAGE` snapshot/log row containing GL balance, reconciled books, export hash evidence, numbering/void/export/artifact/audit evidence, and the snapshot hash/byte size. |
| 12 | Request a package for a period without reconciled books | Rejected (`books_reconciliation`) instead of producing a weak audit package. |
| 13 | Request an unknown book type, inverted range, or blank file name | Rejected with explicit errors. |

Notes:

- All seven books pages previously assembled CSVs in the browser; they now download the exact file text rendered by the RPC and frozen in the snapshot payload. The print views still render live page data.
- Books exports now block on source/GL reconciliation before snapshot/log creation; audit packages block unless the range has reconciled book snapshots and export hash evidence.
- Cash receipts book = ORs (gross of CWT) plus cash-sale SIs; cash disbursements book = PVs (net of EWT) plus check vouchers (net check amount) plus cash purchases.

## JE-DIMS-001 - Dimension Propagation to Journal Entry Lines

Status: Executed Passing (2026-07-04) in `supabase/tests/019_je_line_dimensions_test.sql`.

Related findings: PXL-DA-017 (dimension propagation per DEC-011).

Scenario (two companies; company 1 has branch HO, department FIN, cost center CC-01; company 2 owns a foreign branch/department used only for negative tests):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Post an SI captured under branch HO | The JE header carries the document branch; every JE line inherits it (no line left unattributed, single distinct branch). |
| 2 | Post a manual JE with department/cost center on the expense line | `fn_post_manual_je` accepts per-line `branch_id`/`department_id`/`cost_center_id` in `p_lines`; lines without an explicit branch inherit the header branch. |
| 3 | Reverse the manual JE | Reversal lines carry the original line dimensions (department and cost center preserved on the swapped lines). |
| 4 | Header branch from another company | Rejected by `trg_je_dimensions_guard` ("does not belong to company"). |
| 5 | Line department or line branch from another company | Rejected by `trg_je_line_dimensions_guard`. |
| 6 | Attempt to diverge a line's company from its JE's company | Blocked (RLS filters the direct update; the guard raises in definer contexts) — post-state proves the company is unchanged. |
| 7 | Read `vw_general_ledger` | Line `department_id`/`cost_center_id` are exposed; `branch_id` is line-accurate (`COALESCE(line, header)`), and branch P&L revenue for HO reconciles exactly to the posted SI (10,000.00 net of VAT). |

Notes:

- Lines inherit the header branch centrally in a BEFORE trigger, so all 34 JE writers (and future ones) propagate without per-writer changes; existing lines were backfilled from their headers.
- Documents do not yet carry department/cost center; capture at document-line level is a backlog enhancement (Dimension summary on documents). Stock transfer JEs stay branch-unattributed by design (they span warehouses).

## IMMUT-001 - Status-Aware Immutability on Transactional Headers and Lines

Status: Executed Passing (2026-07-04) in `supabase/tests/020_status_immutability_test.sql`.

Related findings: PXL-DA-011 (posted immutability coverage), PXL-AUD-005 (posted document immutability).

Scenario (one company; posted SI with its JE, an approved CM, and an approved quotation are COMMITTED first, then every tamper attempt runs in its own transaction — the PostgREST client surface; assertions run as postgres, proving the trigger guards hold beneath RLS for any role):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Construct a posted JE inside an open transaction | `fn_row_written_by_current_txn` recognizes the row as ours (the same-transaction construction exception that lets every posting writer insert a posted JE header then its lines). |
| 2 | From a new transaction: update/delete/inject posted JE lines | All three blocked by `fn_guard_doc_lines` ("cannot be changed"). |
| 3 | From a new transaction: change posted JE description or totals; delete the JE | Blocked by `fn_guard_doc_header` ("immutable" / "cannot be deleted"); the committed row is no longer recognized as ours. |
| 4 | Change posted SI total or customer snapshot; delete the SI | Blocked — business columns are frozen outside draft; DELETE always blocked outside draft (DEC-002). |
| 5 | Full-payload re-save of the posted SI with unchanged values | Tolerated — only genuinely changed columns are checked, so UI-style full-payload saves of identical values pass. |
| 6 | `fn_void_sales_invoice` on the guarded posted SI | Controlled void still works: SI reaches `cancelled`, original JE transitions to `reversed` (status + reversal linkage are allowlisted lifecycle metadata). |
| 7 | Inject/update/delete approved CM lines; change CM business fields | Blocked — CM lines are draft-only outside the constructing transaction; header business fields frozen. |
| 8 | `fn_save_credit_memo(..., 'applied')` on the approved CM from a new transaction | Controlled apply still works (the RPC's interim totals rewrite is allowlisted); CM reaches `applied` linked to its JE. |
| 9 | Update approved quotation lines/total; delete the quotation | Blocked — direct-write document families (quotations/SO/DR) are guarded the same way. |

Notes:

- Unlike other test files, this file COMMITs its fixtures: the same-transaction construction exception would otherwise make every tamper attempt look legitimate. Always run on a fresh database (`supabase db reset --local`), per the standing discipline.
- Guards cover every transactional line table (18 tables incl. JE lines; SI/OR/VB/PV keep their PXL-AUD-005 triggers) and every transactional header (34 tables: AR/AP documents, banking, inventory, fixed assets, schedules and their entries — posted entries fully frozen — plus non-VAT tax returns; `vat_returns` stays under the PXL-DA-015 snapshot guard).

## EWT Audit Scenarios (Session 47) — Recommended

The 2026-07-04 EWT end-to-end audit (findings PXL-AUD-031..049) identified the following missing scenarios. Scenarios still marked **Not Yet Implemented** have no `supabase/tests` file yet; they become executable when their finding's fix session lands. CWT-NET-BASE-001 was implemented in session 49.

## CWT-NET-BASE-001 - Statutory VAT-Exclusive CWT on Receipts

Status: Executed Passing (2026-07-04) in `supabase/tests/021_receipt_cwt_net_base_test.sql`.

Related findings: PXL-AUD-031 (fixed, session 49), PXL-AUD-045 (OR default slice delivered with it; PV slice remains).

Scenario (VAT company; posted SI 11,200.00 = 10,000.00 net + 1,200.00 output VAT; customer withholds 2% on the net base):

| Step | Transaction | Amounts | Expected Behavior |
| ---- | ----------- | ------- | ----------------- |
| 1 | OR: cash 11,000.00 + CWT 200.00 on explicit base 10,000.00 | 2% ATC | Accepted (previously REJECTED); JE DR cash 11,000 / DR CWT receivable 200 / CR AR 11,200; SI cleared to zero. |
| 2 | Tax ledger row | - | cwt_receivable base 10,000.00 (net of VAT), tax 200.00; SAWT income payment excludes VAT. |
| 3 | Validator mechanics | - | Legacy gross convention (no explicit base → fallback payment + CWT) still validates; CWT off-rate on the explicit base rejected without a variance reason; accepted with an authorized reason; unrecognized reason rejected (PV parity). |
| 4 | Partial collection: half the invoice, CWT 100.00 on explicit base 5,000.00 | - | Posts; tax ledger row base 5,000.00 / tax 100.00; SI outstanding 5,600.00. |
| 5 | Cash sale with CWT 200.00 (net convention) | 2% ATC | Posts; tax ledger base 10,000.00; receipt JE debits cash 11,000.00. Gross-convention 224.00 records base 11,200.00. CWT matching neither convention rejected with both expected values. |

## CV-EWT-2307-001 - Check Voucher EWT Feeds Certificates and Cancels Cleanly

Status: Executed Passing (session 57, 2026-07-05) — `supabase/tests/022_cv_ewt_2307_test.sql`, 17 assertions. Related findings: PXL-AUD-032, PXL-AUD-033, PXL-AUD-049.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | CV with EWT to a supplier-linked payee, valid ATC, explicit base 10,000 at 2% | Posts; rate-on-base validated like PV lines (off-rate accepted only with an authorized variance reason); JE balanced at gross 10,000 with EWT payable credited 200; tax detail row carries counterparty_id + supplier master TIN/name. |
| 2 | CV EWT without a supplier / wrong rate without reason / expired ATC | Rejected with the PV-style messages at save time (header trigger) and again at post. |
| 3 | Quarterly 2307 generation for a quarter containing CV EWT | Generates (previously ABORTED the whole batch); CV amounts included per supplier/ATC; supplier-unlinked legacy rows are skipped with `skipped_unlinked_count` in the result; an all-unlinked quarter raises an actionable message. |
| 4 | Cancel the posted CV | Counter tax row with `reverses_tax_detail_id`, dated on cancel date; `vw_ewt_summary_ap` drops both rows; QAP detail excludes the cancelled CV. |

## WITHHOLDING-TRACE-DRILLDOWN-001 - EWT/CWT Tax-Ledger, QAP, and Form 2307 Drilldowns

Status: Executed Passing (session 94, 2026-07-14) — `supabase/tests/048_withholding_trace_drilldowns_test.sql`, 9 assertions. Related findings: PXL-AUD-049, PXL-DA-002.

| Step | Transaction / Trace | Expected Behavior |
| ---- | ------------------- | ----------------- |
| 1 | Check Voucher EWT amount trace with `tax_kind=ewt_payable`, `source_doc_type=CV`, and the CV source id | Resolves one grouped tax trace row for the exact CV source document and exposes the CV tax-detail id and amount. |
| 2 | QAP payee/ATC/nature/rate drilldown for a quarter | Resolves only active source rows matching the supplier, ATC, nature of payment, tax rate, and quarter dates; grouped totals equal the report line. |
| 3 | Form 2307 issued line drilldown | Certificate-line filters (`record_id`, ATC, nature, rate) resolve the contributing source tax-ledger rows instead of every line on the certificate. |
| 4 | Cash-sale CWT amount trace with `tax_kind=cwt_receivable`, `source_doc_type=OR`, and the receipt id | Resolves the exact receipt tax detail and links onward through the source accounting trace. |
| 5 | Cash-purchase line and total EWT traces | CP source-document filters, plus optional line ATC/nature/rate dimensions, resolve the exact cash-purchase EWT evidence. |

## EWT-RETURN-GATE-001 - 1601EQ Reconciliation Gate

Status: Executed Passing (session 58, 2026-07-10) — `supabase/tests/023_ewt_return_gate_test.sql`, 12 assertions. Related findings: PXL-AUD-034, PXL-AUD-041.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Compute 1601EQ for a quarter with posted CV EWT | `fn_compute_ewt_return` returns the quarterly `ewt_payable` ledger totals server-side. |
| 2 | Edit total_ewt_withheld to a diverging figure and set status final | Blocked while figures diverge from the ledger (>0.01), `still_due` breaks the withheld-less-remitted arithmetic, `remitted_prior` is negative, or `fn_wht_gl_reconciliation` fails; draft rows stay free-entry. |
| 3 | Matching figures, reconciled quarter, status final then filed | Allowed; metadata-only updates of the validated return pass; business figures frozen (existing PXL-DA-011 guard). |
| 4 | Uncontrolled manual remittance JE on the EWT Payable control account in the next quarter | That quarter's return cannot be marked final (GL variance) until the PXL-AUD-041 controlled remittance flow exists — but still saves as draft. |

## ATC-ASOF-001 - ATC Validity as of Document Date

Status: Not Yet Implemented. Related finding: PXL-AUD-035.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Backdated PV in an open period using an ATC valid on the PV date but expired today | Accepted (today: rejected). |
| 2 | Backdated PV using an ATC that only became effective after the PV date | Rejected (today: accepted). |
| 3 | Same pair on receipt CWT and CV EWT | Same as-of-document-date behavior. |

## ATC-RATE-VERSION-001 - BIR Rate Change Under the Same ATC Code

Status: Not Yet Implemented. Related finding: PXL-AUD-036.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Deprecate used ATC (rate 1%), create successor with the SAME code, rate 2%, effective from the change date | Succeeds (today: unique violation); `supersedes_atc_code_id` links versions. |
| 2 | PV dated before the change | Validates against 1%; after the change: 2%. |
| 3 | Historical documents and QAP for the old quarter | Reproduce the old rate; certificates report the official code unchanged. |

## WHT-REMIT-001 - Controlled EWT Remittance Keeps Exports Reconciling

Status: Executed Passing (session 78, 2026-07-13) in `supabase/tests/036_withholding_remittance_flow_test.sql`, 18 assertions. Related finding: PXL-AUD-041.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | PV EWT in month 1; remit month-1 EWT on the 10th of month 2 through `fn_save_withholding_remittance` / `fn_post_withholding_remittance` | Remittance JE debits EWT payable and is classified as `WHTREM`, with no new tax-detail withholding event. |
| 2 | Quarter-end QAP export | `fn_wht_gl_reconciliation` excludes the controlled remittance JE from GL-side withholding movement, so the QAP export snapshot succeeds while the original EWT tax ledger still ties to the period's withholding. |
| 3 | 1601EQ `remitted_prior` | Derived and validated from posted EWT remittance records by `fn_compute_ewt_remitted_prior`, not free entry. |
| 4 | CWT application and uncontrolled manual remittance | Controlled CWT application reconciles symmetrically; an uncontrolled `MANUAL` remittance JE on the withholding control account still surfaces as variance. |

## WHT-BASIS-001 - AP EWT Source/Accrual Basis Policy

Status: Executed Passing (session 83, 2026-07-13) in `supabase/tests/037_withholding_basis_policy_test.sql`, 16 assertions. Related finding: PXL-AUD-037.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Source-basis company saves a VAT VB for a supplier with default ATC WC140 | Vendor bill line derives EWT base 10,000.00 and EWT 200.00 from the supplier default; header expected EWT mirrors the line total. |
| 2 | Post the VB | JE debits expense/input VAT, credits AP for net payable 11,000.00, credits EWT Payable 200.00, and writes one VB-sourced `ewt_payable` tax-detail row. |
| 3 | AP aging and WHT reconciliation after VB | AP aging shows only the 11,000.00 cash payable; WHT tax detail reconciles to EWT Payable GL. |
| 4 | Attempt a PV with EWT for the same VB | Rejected: the VB already accrued EWT at source. |
| 5 | Cash-only PV for 11,000.00 | Posts and clears AP without writing duplicate PV `ewt_payable` tax detail; EWT ledger/GL remain at the original 200.00 VB source amount. |

## WHT-PROFILE-001 - Compliance Profile Gates EWT Payable and TWA Defaults

Status: Executed Passing (session 84, 2026-07-13) in `supabase/tests/038_withholding_profile_gates_test.sql`, 11 assertions. Related finding: PXL-AUD-042.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Active compliance profile has `ewt_registered = false` | AP-side EWT payable is disabled for that explicit profile. |
| 2 | Source-basis VB for a supplier with default EWT ATC | Rejected with a non-EWT-registered profile message. |
| 3 | Non-withheld VB for a non-EWT supplier | Allowed; expected EWT remains 0.00. |
| 4 | PV manual EWT and CV EWT under the same non-EWT profile | Both rejected before they can persist/post EWT payable. |
| 5 | Draft 1601EQ/EWT return and QAP snapshot under the non-EWT profile | Both rejected by server-side profile gates. |
| 6 | Profile updated to `ewt_registered = true`, `is_twa = true`, `twa_auto_ewt_enabled = true` | TWA auto-EWT becomes active as of the document date. |
| 7 | Supplier-subject source-basis VB has one inventory-item line and one service/expense line with no explicit ATC | Goods line defaults to WC158 at 1% (100.00 on 10,000.00); service line defaults to WC160 at 2% (200.00 on 10,000.00); VB expected EWT syncs to 300.00. |

## TAX-CODE-VERSION-001 - VAT/PT Rate Effective-Date + Version Governance

Status: Executed Passing (session 85, 2026-07-13) in `supabase/tests/039_tax_code_effective_date_governance_test.sql`, 17 assertions. Related finding: PXL-DA-010.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | `tax_codes`/`vat_codes` schema | Both carry `effective_from` governance columns; the global `tax_codes_code_key` is replaced by version-aware `(code, effective_from)`. |
| 2 | One official code `TESTVAT` at 12% (through 2026-06-30) and a 14% successor (from 2026-07-01) | Both versions coexist; a duplicate `(code, effective_from)`, an overlapping active window, and a successor starting before its predecessor are all rejected. |
| 3 | `fn_tax_code_version_asof('TESTVAT', <date>)` | A March 2026 document resolves to the 12% version; an August 2026 document resolves to the 14% successor. |
| 4 | The 12% version is referenced by a posted tax-ledger row, then edited/deleted | `fn_tax_code_used` reads true; its rate, effective-start, and code are frozen; it cannot be deleted; the unused 14% successor stays editable. |
| 5 | A VAT code used through the tax ledger, then re-pointed | The tax code reads as used through its VAT code; the used VAT code's classification is frozen. |
| 6 | Deprecate the 12% version after the 14% successor exists | The historical 12% version keeps its 12.00 rate, so historical VAT/PT reports remain unchanged. |

## FINANCIAL-CLOSE-001 - JE Classification, Trial Balance Modes, and Year-End Close

Status: Executed Passing (session 86, 2026-07-13) in `supabase/tests/040_financial_close_readiness_test.sql`, 17 assertions. Related findings: PXL-AUD-013, PXL-DA-014.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Post a regular revenue JE (100,000) and a regular expense JE (30,000) | Both post; `fn_post_manual_je` stores `entry_class='regular'` by default. |
| 2 | Post a 5,000 rent accrual with `p_entry_class='adjusting'` | Posts with `entry_class='adjusting'`; a manual JE with `p_entry_class='closing'` is rejected. |
| 3 | Unadjusted vs adjusted Trial Balance for the rent expense account | Unadjusted (regular+opening) = 30,000; adjusted (+adjusting) = 35,000. |
| 4 | `fn_close_fiscal_year` for the open year | Posts one balanced closing journal (`entry_class='closing'`, `reference_doc_type='CLOSE'`); returns the JE id. |
| 5 | Post-closing Trial Balance (regular+opening+adjusting+closing) | Revenue and expense accounts net to zero; retained earnings carries net income 100,000 − 35,000 = 65,000. |
| 6 | Fiscal year + periods after close | Year status = `closed`, all periods `is_locked`; re-closing the year is rejected. |

## TRANSACTION-EVENTS-001 - Semantic Transaction Lifecycle Events

Status: Executed Passing (session 87, 2026-07-13) in `supabase/tests/041_transaction_events_test.sql`, 14 assertions. Related finding: PXL-DA-016.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Post a manual journal entry with an authenticated actor | `transaction_events` records a POSTED event with company, source, source document number, actor id, actor role, and linked JE evidence. |
| 2 | Attempt direct application-role insert into `transaction_events` | Rejected; application users can read through RLS but cannot write lifecycle evidence directly. |
| 3 | Reverse the posted JE with a reason | A REVERSED semantic event is written and the legacy `sys_audit_logs` posting_event row remains present with a link back to `transaction_events`. |
| 4 | Insert/update approval evidence | `approval_instances` writes APPROVED lifecycle evidence with actor and status transition context. |
| 5 | Insert a report snapshot export | `report_snapshots` writes EXPORTED evidence so filed/exported report activity appears in the same lifecycle stream. |
| 6 | Read as a non-member | RLS returns zero lifecycle events for another company's user. |

## PV-OR-HEADER-TOTALS-001 - Header/Line Cash Total Integrity

Status: Not Yet Implemented. Related findings: PXL-AUD-038, PXL-AUD-048.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | `fn_save_payment_voucher` with header total_amount ≠ SUM(line payment_amount) | Rejected (or header recomputed server-side). |
| 2 | Same for `fn_save_receipt` | Rejected/recomputed. |
| 3 | GL EWT credit vs tax-ledger EWT sum for the document | Exactly equal (line-sum posted), so WHT/GL reconciliation stays at zero variance. |

## CM-VC-OVERAPPLY-001 - Over-Application Guards Respect Credit Documents

Status: Not Yet Implemented. Related finding: PXL-AUD-039.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | SI 11,200 with applied CM 2,000; receipt for 11,200 | Rejected: exceeds CM-adjusted balance 9,200. |
| 2 | VB 5,600 with applied VC 1,000; PV paying 5,600 | Rejected: exceeds VC-adjusted balance 4,600. |
| 3 | Receipt/PV for the adjusted balance | Accepted; aging reaches zero, never negative. |

## CASH-PURCHASE-EWT-001 - Withholding on Cash Purchases

Status: Executed Passing (session 88, 2026-07-13) in `supabase/tests/042_cash_purchase_ewt_test.sql`, 10 assertions. Related finding: PXL-AUD-043.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Cash purchase of services from an EWT-subject supplier with ATC + explicit net base | Header stores gross VAT totals plus `total_ewt_amount`; `total_amount` is net cash paid. |
| 2 | Post the cash purchase | Posts DR expense/input VAT, CR EWT payable, CR cash net of EWT; JE totals equal gross purchase value. |
| 3 | Tax detail / WHT reconciliation | Writes a source-line `ewt_payable` tax-detail row with ATC, explicit base, supplier TIN/name, and income nature; `fn_wht_gl_reconciliation` ties EWT tax detail to the EWT payable GL control. |
| 4 | Company active compliance profile is not EWT registered | EWT cash purchase save is blocked by the profile gate. |
| 5 | ATC amount does not match explicit base/rate | Save is rejected unless a controlled variance reason is supplied. |

## ADVANCE-PAYMENT-WHT-001 - Withholding on Customer Advances and Supplier Down-Payments

Status: Executed Passing (session 89, 2026-07-14) in `supabase/tests/043_advance_payment_withholding_test.sql`, 13 assertions. Related finding: PXL-AUD-043.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Save an Official Receipt customer-advance line with no SI, CWT ATC/base/amount, and net cash received | Save succeeds as `customer_advance`; posting is blocked until `customer_advances_account_id` is configured. |
| 2 | Post the customer-advance OR after configuring the clearing account | Posts DR cash, DR CWT receivable, CR customer advances; writes source-line CWT tax detail; WHT reconciliation ties tax detail to GL. |
| 3 | Save a Payment Voucher supplier down-payment with no VB and EWT while the company profile is not EWT-registered | Save is blocked by the EWT profile gate. |
| 4 | Save/post the supplier down-payment after enabling EWT and configuring the clearing account | Saves as `supplier_down_payment`; posting is blocked until `supplier_down_payments_account_id` is configured, then posts DR supplier down payments, CR cash, CR EWT payable; writes source-line EWT tax detail; WHT reconciliation ties tax detail to GL. |

## SETUP-READINESS-001 - Guided Minimum Accounting Setup

Status: Executed Passing (session 59, 2026-07-10) via production build, zero-warning lint, and transaction/checklist code-path inspection. Related finding: PXL-AUD-002.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Open a company's Checklist from Company Setup | One progress view verifies the legal profile, active branch, current fiscal year/open period, all five active postable COA types, SI/OR/VB/PV series per branch, matching compliance profile, applicable VAT/ATC/company tax codes, and applicable GL mappings. |
| 2 | Open an incomplete checklist item | The app selects that company as context, clears stale branch/period context, and navigates to the owning setup page. |
| 3 | Attempt SI/OR/VB/PV or CM/DM/cash sale/cash purchase/vendor-credit work with a missing branch, period, number series, or applicable GL mapping | Save/post is disabled and the banner lists the exact blockers with a link back to Company Setup. |
| 4 | Use a non-VAT transaction or a payment/receipt with no withholding | VAT/CWT/EWT account mappings that the transaction will not use do not falsely block it; the relevant account becomes required when VAT or withholding applies. |

## VAT-REG-ALL-DOCS-001 - Registration Enforcement Across VAT Documents and Exports

Status: Executed Passing (session 59, 2026-07-10) in `supabase/tests/024_vat_registration_all_documents_test.sql`, 35 assertions. Related findings: PXL-AUD-006, PXL-AUD-014, PXL-DA-008.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Non-VAT/exempt company attempts regular VAT CM, DM, cash purchase, vendor credit, or cash sale | Rejected at the line/header database boundary; positive VAT cannot be hidden behind a zero-rate or NULL code. |
| 2 | Use an input code on output documents or an output code on input documents | Rejected for wrong VAT direction. |
| 3 | Post valid VAT-company CM/DM/VC documents | Canonical per-code tax-detail rows carry the correct signed base/tax; legacy lump rows from the wrapped writer are replaced in the same transaction. |
| 4 | Authenticated user directly inserts/updates/deletes `tax_detail_entries` | Denied; SECURITY DEFINER posting/reversal RPCs remain the only writers. |
| 5 | Non-VAT company requests SLSP/RELIEF through VAT or CAS snapshot entry points, or inserts a VAT export snapshot | Rejected before export evidence is created; non-VAT CAS report types remain available. |

## VAT-AMOUNT-INTEGRITY-001 - Server-Authoritative Operational VAT Amounts

Status: Executed Passing (session 62, 2026-07-12) in `supabase/tests/028_vat_amount_integrity_test.sql`, 25 assertions. Related findings: PXL-DA-008, PXL-AUD-014.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Submit forged line net/VAT/total fields and forged header totals through SI, VB, CM, DM, cash-purchase, and vendor-credit save RPCs | Every derived field is ignored; the server recomputes line and header amounts from quantity/price/discount plus the VAT classification/rate masters. |
| 2 | Post mixed regular/zero-rated/exempt SI and VB fixtures | Per-code tax detail preserves every classification base; document totals, output/input VAT GL controls, and ledger-backed VAT review rows match exactly. |
| 3 | Inspect application-role grants and RLS policies on all six VAT headers/line tables and the updatable SI/VB register views | SELECT remains available through company-scoped RLS, but INSERT/UPDATE/DELETE/TRUNCATE grants and mutation policies are absent. The register views run as `security_invoker`. |
| 4 | As `authenticated`, directly alter a base header/line, update an updatable register view, or truncate source evidence | Rejected with table/view-permission denial; register reads expose no foreign-company rows. |
| 5 | As `authenticated`, edit a draft document through its SECURITY DEFINER save RPC | Allowed; the normal application workflow remains operational and server-authoritative. |

## GL-PREVIEW-PARITY-001 - Exact Rollback Preview and Posting Invariants

Status: Executed Passing (session 59, 2026-07-10) in `supabase/tests/025_posting_preview_invariants_test.sql`, 40 assertions. Related findings: PXL-DA-001, PXL-DA-002, PXL-DA-004, PXL-DA-005, PXL-DA-006, PXL-DA-007.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Preview an approved SI, then post it | Preview executes the real posting RPC in a rollback-only subtransaction: source status, JE, and tax ledger remain unchanged; preview account/debit/credit rows exactly equal the later posted JE. |
| 2 | Preview amortization and a recurring template for an operator-selected date | Exact two-line impacts are returned; schedule status/date advancement and all JEs roll back. The recurring payload uses the selected date. |
| 3 | Link fixed-asset acquisition/depreciation and schedule journals | Registry contains every active writer type; source IDs point to the actual asset/entry, not an ambiguous parent. |
| 4 | Request accounting trace by source or JE | Stable source/JE/GL routes resolve; a mismatched source type/ID and JE is rejected. |
| 5 | Attempt duplicate live source JE, inactive account line, wrong fiscal period, unknown source type, or direct internal mutation primitive | Each attempt is rejected centrally. |
| 6 | Preview a document in a locked period | The same locked-period error as posting is returned and the source remains unchanged. |

## ACCOUNTING-TRACE-REPORTS-001 - Report-Wide Drillback Trace Contracts

Status: Executed Passing (session 63, 2026-07-12) in `supabase/tests/026_accounting_trace_report_routes_test.sql`, 29 assertions. Related findings: PXL-DA-002, PXL-DA-005.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Read customer/supplier ledger and VAT/EWT/CWT review views | Every row carries the canonical `source_doc_type`/`source_doc_id` pair pointing at its posted source document. |
| 2 | Request a single-source accounting trace | The trace resolves the generic read-only `/accounting-source` route plus the linked JE; a JE paired with an arbitrary or mismatched source fails closed. |
| 3 | Create deliberate orphan and cross-company source links via replica-mode fixtures | The trace reader rejects them; no foreign-company source record is ever returned to a member of another company. |
| 4 | Request report snapshot trace links | Links are derived read-only from the immutable snapshot payload; payloads and hashes are never rewritten. |
| 5 | Request aggregate report trace sets by family (financial, subledger, tax, 2307, snapshot) | Row sets are membership-scoped to the caller's company and filtered by the family's filter keys. |
| 6 | With `SET CONSTRAINTS trg_journal_entry_source_integrity IMMEDIATE`, insert posted JEs under normal trigger execution: one referencing a live same-company SI, one referencing a nonexistent SI, one referencing another company's SI | The live-source JE is accepted; the orphan-source and cross-company JEs are rejected by the real writer-boundary constraint at statement time (PXL-DA-005 closure evidence). |

## POSTING-RACE-001 - Genuine Two-Session Posting Race and Idempotency

Status: Executed Passing (session 63, 2026-07-12) in `supabase/tests/029_posting_race_two_session_test.sql`, 14 assertions. Related findings: PXL-DA-007, PXL-DA-004.

Local-harness-only by design: the test opens two extra real database sessions with dblink through the same TCP endpoint the pgTAP harness uses, so its fixture company is committed, pre-cleaned on entry, and deleted on exit (rerunnable back-to-back).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Build a committed approved SI through the governed save/approve RPCs in an autonomous setup session | A single approved sales invoice exists as the race target. |
| 2 | Session A begins a transaction and posts the SI without committing | Session A holds the governed `FOR UPDATE` source lock. |
| 3 | Session B posts the same SI concurrently | Session B observably blocks on the source lock (`pg_stat_activity` shows a `Lock` wait). |
| 4 | Session A commits | Session B resumes without error and resolves to a governed no-op: exactly one original JE and one live output VAT tax set exist, and the SI links the single surviving JE. |
| 5 | Re-post the same SI sequentially afterward | Idempotent no-op; no additional JE or tax rows. |
| 6 | Directly insert a second live original JE or a second live VAT tax row for the raced source | Structurally impossible: rejected by `ux_journal_entries_live_source` and `ux_tde_vat_source_code`. |
| 7 | Delete the committed fixture company | Nothing is left behind; the test is rerunnable. |

## CAS-E2E-DRAFT-027 - CAS End-to-End Control Scenario

Status: Executed Passing (2026-07-22 release-gate validation) in `supabase/tests/027_cas_end_to_end_controls_test.sql`, 34/34 assertions and included in the complete 74-file lane.

Notes:

- This scenario was originally held out while CAS allocator and document-period behavior were incomplete. Migrations through `20260721000003_aud066_cas_document_period_evidence.sql` resolved those defects, and no test file is now excluded from the governed regression lane.
- Complementary CAS evidence remains in `supabase/tests/030_document_numbering_registry_test.sql`, `supabase/tests/031_posting_runtime_repairs_test.sql`, and `supabase/tests/032_cas_numbering_void_evidence_test.sql`.

## DOCUMENT-NUMBERING-REGISTRY-001 - Document-Code Registry and Branch-Scoped Numbering

Status: Executed Passing (session 63, 2026-07-12) in `supabase/tests/030_document_numbering_registry_test.sql`, 11 assertions. Related findings: PXL-AUD-051.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Extract every document code passed to `fn_next_document_number` by shipped functions and left-join `ref_document_types` | Zero unmatched codes — the registry covers every consumer (JE, FA, SDM, PRT included). |
| 2 | Scan every deployed function for a two-argument `fn_next_document_number(company, code)` call | Zero remain; numbering is always per company+branch+code (DEC-006). |
| 3 | Check the registry for `JE`, `FA`, `SDM`, `PRT`, and `DM-S` | All governed (the four added codes plus the code `DebitMemosPage` readiness now uses). |
| 4 | Register a fixed asset through `fn_register_fixed_asset` with a branch-scoped FA and JE series | The asset number is `FA-2026-…`, the acquisition journal number is `JE-2026-…`, the JE posts balanced, and it links back to the asset as an `FA` source (previously the branch-less numbering aborted the RPC). |
| 5 | Call the branch-scoped `fn_next_document_number(company, branch, 'JE')` used by the inventory posters | Resolves and increments against a registry-consistent setup. |

## POSTING-RUNTIME-REPAIRS-001 - Physical Count, Stock Transfer, and Purchase-Return Posting Repairs

Status: Executed Passing (session 64, 2026-07-12) in `supabase/tests/031_posting_runtime_repairs_test.sql`, 49 assertions. Related findings: PXL-DA-019 (prerequisite runtime defects surfaced by schema lint before CAS work).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Assert schema shape after the repair migration | `physical_count_sheet_lines.variance_cost` does not exist (variance stays derived), and `vendor_bills.rr_id` exists as an optional receiving-report link. |
| 2 | Post a physical count with a nonzero variance | Posting succeeds without referencing the removed derived column; the applied unit cost is frozen on the count line and the derived +20.00 variance cost lands on the immutable inventory transaction, raising source stock 10→12 and cost 100.00→120.00. |
| 3 | Inspect the physical-count JE | Draws the first governed source-branch JE number, records a balanced 20.00 debit/credit, debits inventory and credits the variance account by the derived cost. |
| 4 | Post a cross-warehouse stock transfer with different GL accounts | Posts successfully; the JE number comes from the source warehouse branch series (the destination branch series is not consumed) while the JE itself stays branch-unattributed; debits destination and credits source inventory. |
| 5 | Save vendor bills against receiving reports through `fn_save_vendor_bill` | Rejects an RR that is not received and an RR belonging to another supplier; still accepts a bill with no RR (link stays NULL) and a received same-company/same-supplier RR (link persisted and durable across approve/post). |
| 6 | Complete a purchase return against the linked RR | Fails closed when the RR has no linked posted bill; with the restored explicit link it completes without error, reaching `completed` with a reversing JE that uses the governed source-branch JE series, the return date (not execution date) for period resolution, the `PR` source type, and a balanced 20.00 AP-debit / matched-purchase-expense-credit reversal linked back to the source. |

## CAS-NUMBERING-VOID-EVIDENCE-001 - Governed Document Numbering and Immutable Void Evidence

Status: Executed Passing (session 64, 2026-07-12) in `supabase/tests/032_cas_numbering_void_evidence_test.sql`, 25 assertions. Related findings: PXL-DA-019.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Allocate two ordinary (non-ATP) JE numbers directly through `fn_next_document_number` | Sequential `JE-000001`/`JE-000002`; both unresolved reservations remain visible as accountable evidence — a reservation is evidence, not a session-wide lock blocking the next allocation. |
| 2 | Save an ATP-authorized SI (range 100–101) | Receives sequence 100 with frozen formatting `SI-000100`; the reservation is atomically bound to the saved source as an `issued` evidence row. |
| 3 | Approve, post, then void the SI through the real RPCs with an explicit reason | The source reaches `cancelled`; the same immutable issuance row is marked `voided` (never deleted or reusable). |
| 4 | Inspect the captured void event | Freezes reason, actor, and original/reversal JE links; `source_snapshot` retains the pre-void (`posted`) document content; the links resolve to the reversed original and posted reversal JEs. |
| 5 | Attempt to mutate void evidence as the table owner | Rejected with `P0001` — terminal-document evidence is immutable to any statement, including the owner. |
| 6 | Save a second SI, then attempt a third beyond the ATP range | The second consumes 101 (never reusing voided 100); the third fails with `ATP range exhausted` and does not drift the governed counter (`current_sequence` stays 101), and no evidence is created beyond the authorized range. |
| 7 | As an application (`authenticated`) caller, attempt to roll the counter back, rewrite number formatting, or directly mutate/delete issuance/void evidence | All rejected: `P0001` for backward/format changes on `number_series`; `42501` for direct DML on the evidence tables (RLS/grants). |
| 8 | Read `vw_cas_atp_usage` for the SI series | Reports issued/voided counts and `is_exhausted`/alert-threshold status from evidence (0 reserved, 1 issued, 1 voided, 2 allocated, 0 remaining, 100.00% used, exhausted). |

## ATC-DOCDATE-VERSION-001 - Document-Date ATC Validation and Effective-Dated Rate Versioning

Status: Executed Passing (session 77, 2026-07-13) in `supabase/tests/033_atc_document_date_versioning_test.sql`, 15 assertions. Related findings: PXL-AUD-035, PXL-AUD-036 (safe trusted replacement for the held-out draft `20260710000004`).

Scenario: official ATC `WI777` withholds 1% through 2026-06-30 and 2% from 2026-07-01 (a BIR rate change under the same official code), created as two effective-dated versions with a successor link.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Resolve the code as of a June and a July date via `fn_atc_version_asof` | Returns the 1% version for the June date and the 2% version for the July date. |
| 2 | Count active rows for the official code | Two effective-dated versions of the same `code` coexist — the former global `UNIQUE (code)` key is replaced by version-aware uniqueness `(code, tax_category, effective_from)`. |
| 3 | Validate PV EWT with the 2% version on a June-dated document | Rejected: the version is not effective on the document date (error names the document date, not `CURRENT_DATE`). |
| 4 | Validate PV EWT with the 1% version on a June-dated document, and the 2% version on a July-dated document | Both pass at the amount matching the version's rate on the taxable base. |
| 5 | Validate OR CWT with the 2% version on a June-dated receipt, and the 1% version on a June-dated receipt | The future version is rejected as-of the receipt date; the in-force version validates. |
| 6 | Insert a backdated (June 20) check voucher using the 1% version through `trg_cv_ewt_validation` | Accepted — the CV caller now evaluates ATC validity as of `voucher_date`, so a legitimate backdated document in an open period posts even though the 1% version is expired as of today. |
| 7 | Insert the same backdated CV using the not-yet-effective 2% version | Rejected: the version is not effective on the June voucher date. |
| 8 | Insert a third active version overlapping the open 2% window | Rejected by the version-integrity guard — the prior version's `effective_to` must be closed before a successor starts. |
| 9 | Insert a successor pointing at a predecessor with a different official code | Rejected — a successor must keep the same official code and tax category (alphalists must carry the official ATC). |
| 10 | After the 1% version is used, attempt to move its `effective_from`, close its `effective_to`, or change its `rate` | `effective_from` and `rate` are immutable once used; `effective_to` can still be closed to end the window. |

## SETTLEMENT-TOTAL-AUTHORITY-001 - PV/OR Header Totals Derived From Lines

Status: Executed Passing (session 77, 2026-07-13) in `supabase/tests/034_settlement_total_line_authority_test.sql`, 8 assertions. Related findings: PXL-AUD-038 (header/line divergence), PXL-AUD-048 (tolerance alignment).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save a PV with a bogus header `total_amount` (99,999) and `total_ewt` (88,888); the single line pays 5,000 and withholds 100 (2% of the explicit 5,000 base) | The server ignores the client header and stores `total_amount = 5,000` (the line payment sum). |
| 2 | Inspect the stored header EWT | `total_ewt = 100`, exactly the line EWT sum — the GL figure equals the tax-ledger figure with no 0.02 drift (PXL-AUD-048). |
| 3 | Post the PV | Posts from the line-derived header. |
| 4 | Inspect the posted PV JE cash line | Credits Cash by the line-sum 5,000, not the client header value. |
| 5 | Tamper a saved draft PV header (`total_amount` set to diverge from the lines), then post | Rejected — the readiness validator requires the header cash total to equal the line payment sum before a JE is written. |
| 6 | Save an OR with a bogus header `total_amount` (77,777) and `total_cwt` (55,555); the line collects 11,000 cash and 200 CWT (2% of the explicit 10,000 base) | The server stores `total_amount = 11,000` (the line payment sum). |
| 7 | Post the OR | Posts from the line-derived header. |
| 8 | Inspect the posted OR JE cash line | Debits Cash by the line-sum 11,000, not the client header value. |

## CASH-SALE-RECEIPT-TOTAL-001 - Cash-Sale Receipt Header and Bounce Totals

Status: Executed Passing (session 92, 2026-07-14) in `supabase/tests/046_cash_sale_receipt_total_semantics_test.sql`, 13 assertions. Related findings: PXL-AUD-046.

Scenario: a VAT cash sale for 10,000 net + 1,200 VAT has 200 CWT withheld, creating a linked cash-sale invoice, receipt, receipt line, original OR JE, and later a bounce reversal.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save the cash sale through `fn_save_cash_sale` with WC140 CWT of 200 | The linked receipt stores `total_amount = 11,000` cash received, `total_cwt = 200`, and gross clearance derived as 11,200. |
| 2 | Compare receipt header and receipt-line totals | Header cash/CWT/gross matches line payment/CWT/gross exactly. |
| 3 | Inspect the linked cash-sale invoice | Invoice total remains the gross sale amount of 11,200. |
| 4 | Inspect the original cash-sale OR JE | JE header totals are 11,200 debit and 11,200 credit, matching the JE line sums. |
| 5 | Bounce the cash-sale receipt with `fn_bounce_receipt` | Bounce succeeds, marks the receipt `bounced`, creates a reversal JE linked from the original, and keeps CWT tax detail netted to zero. |
| 6 | Inspect the reversal JE | Reversal totals are 11,200 debit and 11,200 credit, not the overstated 11,400 gross-plus-CWT amount, and header totals equal line sums. |
| 7 | Re-read the bounced receipt header | The corrected cash/CWT/gross split remains 11,000 / 200 / 11,200 after bounce. |

## FORM2307-RECEIVED-CLAIM-001 - Governed Received-Certificate Claims

Status: Executed Passing (session 93, 2026-07-14) in `supabase/tests/047_form2307_received_claim_lifecycle_test.sql`, 18 assertions. Related findings: PXL-AUD-047.

Scenario: a posted receipt with 200 CWT receives customer Form 2307 evidence, the certificate is claimed in an ITR quarter, then the receipt bounces; separately, a sent issued Form 2307 certificate is affected by a later EWT source reversal.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Try recording a received certificate for 201 against a receipt line with 200 CWT | Rejected: certificate amount cannot exceed the receipt-line CWT. |
| 2 | As an authenticated application role, try direct INSERT into `form_2307_tracking` | Rejected by the RPC-only write posture. |
| 3 | Record the certificate through `fn_record_form2307_received` | Succeeds and stores status `received`, exact amount 200, date received, ATC, and covered period. |
| 4 | Try a direct owner update increasing the certificate amount | Rejected by the table guard against the receipt-line CWT ceiling. |
| 5 | Try claiming with invalid quarter 5 | Rejected by the claim RPC. |
| 6 | Claim through `fn_claim_form2307_received` for Q1 2026 | Succeeds and records status `claimed`, claim year/quarter, claimed timestamp, and actor. |
| 7 | Try direct mutation of the claimed row and try re-recording it through the receive RPC | Both rejected; terminal evidence is locked. |
| 8 | Bounce the underlying receipt | Succeeds, nets OR CWT tax detail to zero, and marks the linked received certificate `invalidated` with a reason. |
| 9 | Try claiming the invalidated certificate | Rejected because only `received` rows can be claimed. |
| 10 | Generate and send an issued Form 2307 certificate from AP EWT detail, then cancel the source PV | The sent certificate remains immutable evidence but is flagged `requires_supersede` with a reason derived from the EWT reversal. |

## HEAVY-REPORT-READINESS-001 - Server-side GL Pagination and TB Aggregation

Status: Executed Passing (session 98, 2026-07-14) in `supabase/tests/052_heavy_report_readiness_test.sql`, 18 assertions. Related finding: PXL-DA-018.

Scenario: a company has an opening balance before the report range, 25 regular revenue journals, and 5 adjusting expense journals in January 2026.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Read January GL through `fn_general_ledger_report` with a page size of 7 | Returns only 7 rows, while exposing total filtered rows and full-period debit/credit totals independent of page size. |
| 2 | Apply account-type and entry-class filters to the GL report | Filtering runs server-side and returns only matching regular revenue lines. |
| 3 | Request an invalid small page limit | The server clamps the limit to one row instead of allowing an unbounded or invalid request. |
| 4 | Read Cash through `fn_gl_account_ledger_summary` | Opening balance, period debit, period credit, closing balance, and total movement rows are computed server-side. |
| 5 | Read page 2 of Cash through `fn_gl_account_ledger_page` | Returns the requested page size, and the first row's running balance includes all rows before the page offset. |
| 6 | Apply a JE drilldown filter to the account ledger page | The page returns only the selected JE's account line without loading the full period. |
| 7 | Read Trial Balance through `fn_trial_balance_report` in unadjusted and adjusted modes | Unadjusted excludes adjusting entries; adjusted includes them; the adjusted TB remains balanced. |

## SI-EXPECTED-CWT-OR-001 - SI Expected CWT to OR Carry-Forward

Status: Executed Passing (session 100, 2026-07-14) in `supabase/tests/053_si_expected_cwt_receipt_flow_test.sql`, 9 assertions. Related finding: PXL-AUD-045.

Scenario: a VAT sales invoice has 10,000 VAT-exclusive income and the customer default CWT ATC is WC140 at 2%.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save the SI with expected CWT 210 | Rejected because WC140 on a 10,000 base expects 200. |
| 2 | Save the SI with a non-default CWT ATC | Rejected because SI expected CWT must match the customer default ATC. |
| 3 | Save the SI with expected CWT 200 and no explicit base | Succeeds and stores WC140 plus a 10,000 VAT-exclusive CWT base. |
| 4 | Approve and post the SI | Both lifecycle transitions succeed. |
| 5 | Save and post an OR applying 11,000 cash plus 200 CWT to the SI | The receipt line and CWT tax detail carry WC140, base 10,000, and CWT 200; AR is cleared by cash plus CWT. |

## SALES-INVOICE-COMPLETENESS-001 - Sales Invoice VAT Basis, Dimensions, Inventory, and Void Restoration

Status: Executed Passing (session 101, 2026-07-15) in `supabase/tests/054_sales_invoice_completeness_test.sql`, 18 assertions. Related finding: PXL-AUD-053.

Scenario: a VAT-inclusive Sales Invoice contains one inventory item line and one service line, with Department, Cost Center, Warehouse, Salesperson, and Account Owner sourced from governed master data.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save the SI with VAT Price Basis = VAT Inclusive | The invoice persists `vat_price_basis = inclusive`; server-computed net/VAT/gross totals are 1,500 / 180 / 1,680. |
| 2 | Inspect line values | The inventory line is 1,000 net + 120 VAT = 1,120 gross; the service line is 500 net + 60 VAT = 560 gross. |
| 3 | Inspect dimensions | Header stores Department, Cost Center, Warehouse, Salesperson, and Account Owner; inventory line inherits warehouse, while the service line does not automatically receive warehouse context. |
| 4 | Approve and post the SI | Posting succeeds through the governed RPC. |
| 5 | Inspect GL impact | JE includes DR AR 1,680; CR product revenue 1,000; CR service revenue 500; CR output VAT 180; DR COGS 600; CR Inventory 600, and remains balanced. |
| 6 | Inspect inventory evidence | Inventory line stores unit cost 600, inventory cost 600, and an inventory transaction link; service line has no inventory evidence. |
| 7 | Inspect stock and tax ledger | Stock falls from 5 units / 3,000 cost to 4 units / 2,400 cost; tax detail stores VAT base 1,500, VAT 180, and normalized customer TIN. |
| 8 | Void the posted SI | Void creates a reversal journal, restores stock to 5 units / 3,000 cost, and writes an `SI_VOID` inventory restoration transaction. |

## CANONICAL-DEMO-DATASET-001 - Canonical Demo Seed and Inventory Control Regression

Status: Executed Passing (session 102, 2026-07-16) in `supabase/tests/055_canonical_demo_dataset_test.sql`, 34 assertions when the canonical demo seed is loaded. Related finding: PXL-AUD-054.

Scenario: the canonical demo dataset is loaded after the controlled reset and validates the primary VAT trading company plus representative non-VAT, service, purchasing, inventory, tax, and accounting flows.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Load `canonical_demo_seed.sql` after `canonical_demo_reset.sql` | Five demo companies exist with supported entity/tax profiles; the primary VAT trading company has 3 branches, 5 departments, 5 cost centers, 3 warehouses, 10 customers, 10 suppliers, 9 stock items, 6 service items, approval fixtures, and core number series. |
| 2 | Inspect VAT-exclusive and VAT-inclusive Sales Invoices | VAT-exclusive 2,000 produces 240 VAT and 2,240 gross; VAT-inclusive 1,120 persists `vat_price_basis = inclusive` and recomputes 1,000 net / 120 VAT / 1,120 gross. |
| 3 | Inspect expected CWT versus actual CWT | Sales Invoice stores expected CWT only; Official Receipt records actual CWT, receipt line base, and `cwt_receivable` tax detail at collection time. |
| 4 | Inspect purchasing and AP tax evidence | Posted Vendor Bill creates input VAT and EWT tax detail; partial Payment Voucher posts with the expected payment amount. |
| 5 | Inspect inventory movements and balances | Opening inventory, SI issue, receiving report inventory receipt, transfer, and adjustments reconcile to warehouse-level stock balances with no negative quantities. |
| 6 | Attempt invalid stock transfer | `fn_post_stock_transfer` rejects source-warehouse over-transfer before mutating stock, cost, inventory movements, or JE evidence. |
| 7 | Attempt Sales Invoice oversell | SI can be saved, but approval readiness rejects warehouse-level oversell with an insufficient-stock error and leaves the invoice draft/unposted. |
| 8 | Inspect accounting balance | Posted journals remain balanced at header and line level; primary VAT trading company trial-balance delta is zero. |

Pre-enrichment hosted read-only verification on 2026-07-16 against project `bskjkogijpbhukjkagfj` confirmed the original seeded invariant state without mutating hosted data: 12 canonical posted journals / 0 unbalanced, VAT-exclusive and VAT-inclusive SI math, CWT recognized at OR timing, VB input VAT/EWT, 0 negative stock rows, 0 stock-balance-vs-movement mismatches, AR balance 2,688 across 2 open ABC invoices when evaluated under the demo user's JWT, AP balance 1,664, source-document relationships, and posted status/posting indicators.

Final Phase 3 hosted verification after idempotent incremental enrichment confirmed 48 canonical journals / 0 unbalanced, zero AR/AP reconciliation variance for all five companies, 0 negative-stock rows, 0 stock-balance-vs-movement mismatches, and company AR balances of 3,584.80 / 16,800 / 2,650 / 50,000 / 42,560 for ABC / Bayani / Golden / Northstar / Prime. The corresponding AP balances are 1,440 / 13,310 / 3,000 / 0 / 43,400. This final state is guarded by `PHASE3-CANONICAL-IMPLEMENTATION-001` below.

## COMPANY-RLS-MEMBERSHIP-001 - Company Selector and Cross-Company RLS Scope

Status: Executed Passing (Phase 3, 2026-07-16) in `supabase/tests/056_company_rls_membership_scope_test.sql`, 11 assertions locally and 11 assertions against hosted in a rollback transaction. Related findings: PXL-AUD-062 and PXL-AUD-061.

Scenario: one authenticated owner creates an allowed company, another authenticated owner creates a hidden company, and the first user queries company selector, branch, customer, and Sales Invoice surfaces under RLS.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Query `companies` as the allowed-company owner | Only the allowed company is visible, matching the company selector's membership scope. |
| 2 | Query the hidden company directly | The non-member company is invisible. |
| 3 | Attempt to update the hidden company | No hidden company row is targeted or changed. |
| 4 | Query branches and customers | Only allowed-company branch and customer rows are visible. |
| 5 | Query Sales Invoices | Only allowed-company transaction rows are visible. |
| 6 | Query companies as a user with no memberships | Zero companies are visible. |

## PHASE3-CANONICAL-IMPLEMENTATION-001 - Differentiated Multi-Company ERP Regression

Status: Executed Passing (Phase 3, 2026-07-16) in `supabase/tests/057_phase3_canonical_implementation_test.sql`, 38 assertions locally and 38 against hosted. Related findings: PXL-AUD-057, PXL-AUD-059, PXL-AUD-064, and PXL-AUD-067.

Scenario: the base canonical seed is enriched idempotently with differentiated retail, wholesale, OPC service, VAT advisory, and partnership mixed-operations activity.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Apply `canonical_phase3_enrichment.sql` twice | No duplicate business scenarios; stable references and governed official numbers remain intact. |
| 2 | Inspect all five setup profiles | Legal/tax setup, branch, fiscal periods, COA, number series, compliance, ATC/VAT applicability, and GL config are ready; non-VAT VAT steps are not applicable. |
| 3 | Inspect Golden and Bayani inventory companies | Opening, receipt, issue, transfer/adjustment/count movements reconcile to stock with no negative warehouse quantity. |
| 4 | Inspect Northstar and Prime service companies | Service invoices/VBs/JEs post without fake warehouse or inventory requirements. |
| 5 | Inspect ABC lifecycle/corrections | Quotation/SO/DR/SI/OR chain, CM, VC application, cash purchase, count, and SI void/reversal remain source-linked and balanced. |
| 6 | Reconcile tax | VAT-inclusive/exclusive, non-VAT, expected/actual CWT, and source EWT rows reconcile to document and GL evidence. |
| 7 | Reconcile AR/AP | All five company subledgers agree with GL after including original reversed journals and counter-journals. |
| 8 | Inspect posted documents | Posted sources carry posting/audit indicators and remain immutable. |

## CANONICAL-DEMO-VOLUME-001 - Editable High-Volume Transaction Work Queue

Status: Executed Passing (2026-07-18) in `supabase/tests/058_canonical_demo_volume_test.sql`, 16 assertions locally after the atomic canonical rebuild. Hosted execution of `canonical_demo_volume.sql` also completed its inline count assertions; read-only hosted verification confirmed the same counts. The linked pgTAP CLI connector was not counted because its temporary login role lacked direct table permissions.

Scenario: the primary VAT trading company receives additive list-scale masters and draft documents without changing its governed posted accounting evidence.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Apply `canonical_demo_volume.sql` twice | Stable codes/references remain idempotent with 40 additional customers, 30 suppliers, 12 inventory items, and 12 service items. |
| 2 | Inspect Sales Invoices | Exactly 60 two-line SIs exist as editable drafts across all three ABC branches, with positive server-computed totals and valid fiscal periods. |
| 3 | Inspect Purchase Orders | Exactly 30 one-line POs exist as editable drafts against active suppliers and purchase-ready inventory items. |
| 4 | Inspect Vendor Bills | Exactly 30 one-line VBs exist as editable drafts with positive server-computed totals and valid fiscal periods. |
| 5 | Inspect inventory setup | Every new inventory item has replenishment controls in all ABC warehouses; no direct stock balance is fabricated. |
| 6 | Reconcile historical accounting | Draft volume does not change posted accounting evidence; current AR/AP reconciliation remains zero variance for all five companies. |
| 7 | Inspect company readiness | ABC retains three branches, accounting configuration, compliance profile, active number series, and open fiscal periods so each draft can continue through its governed lifecycle. |

## SI-PREVIEW-PERIOD-PARITY-001 - Locked-Period Sales Invoice Preview

Status: Executed Passing (Phase 3, 2026-07-16) in `supabase/tests/025_posting_preview_invariants_test.sql`, 40/40 locally and 40/40 against hosted after `20260716000005`. Related finding: PXL-AUD-065.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Save and approve an SI in a fiscal period | Preview returns the authoritative saved-document impact without persistence. |
| 2 | Lock the covering period for a second approved SI | `fn_preview_gl_impact('SI', ...)` raises `No open fiscal period`, matching posting behavior. |
| 3 | Inspect the rejected preview source | Source remains approved and no JE/tax/inventory rows are written. |

## CAS-HISTORICAL-PACKAGE-001 - Historical Number/Void Evidence

Status: Executed Passing (2026-07-22 release-gate validation) in `supabase/tests/027_cas_end_to_end_controls_test.sql`, 34/34 assertions. PXL-AUD-061 and PXL-AUD-066 are Retested Passed.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Create, post, and void a July 10 SI; generate reconciled books/DAT evidence later | Source documents, journals, number issuance, void event, books, and export artifacts remain immutable. |
| 2 | Generate a CAS audit package for July 10 | Package should include the historical number and void rows based on document period. |
| 3 | Inspect package payload | Package includes the July issuance and void by source-document date while excluding later-period reversal evidence. |

## CM-VC-OVERAPPLY-001 - Over-Apply Guards Net Applied Credit Memos / Vendor Credits

Status: Executed Passing (session 77, 2026-07-13) in `supabase/tests/035_cm_vc_aware_overapply_test.sql`, 6 assertions. Related findings: PXL-AUD-039.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Post an 11,200 SI and apply a 2,000 credit memo (`status = applied`) against it | The invoice's collectible balance is now 9,200 (SI total less applied CM), mirroring `fn_ar_aging_asof`. |
| 2 | Save a receipt collecting the full 11,200 | Rejected — `Payment ... exceeds outstanding balance` — because the applied CM leaves only 9,200 collectible (previously accepted, driving AR negative and inflating the CWT base). |
| 3 | Save a receipt collecting the net 9,200 | Accepted. |
| 4 | Post an 11,200 VB and apply a 2,000 vendor credit against it via `fn_apply_vendor_credit` | The bill's payable balance is now 9,200 (VB total less non-reversed VC application on an open/applied vendor credit), mirroring `fn_ap_aging_asof`. |
| 5 | Save a PV paying the full 11,200 | Rejected — `Payment ... exceeds outstanding AP balance` — because the applied VC leaves only 9,200 payable. |
| 6 | Save a PV paying the net 9,200 | Accepted. |

## GOVERNED-BIR-CONFIG-001 - Governed Global BIR Configuration Write Policy

Status: Executed Passing (2026-07-20) in `supabase/tests/059_aud063_governed_bir_config_test.sql`, 22 assertions locally after a clean `supabase db reset` replay including migration `20260720000001_aud063_governed_bir_config_policy.sql`. Related finding: PXL-AUD-063.

Scenario: the global statutory tables `bir_forms` and `bir_form_mappings` are read-only for ordinary authenticated users, and all writes flow through a single governed SECURITY DEFINER RPC path gated by the default-empty `bir_config_maintainers` allowlist with audit-trail evidence.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Read `bir_forms`/`bir_form_mappings` as an ordinary authenticated user | Reads succeed; global BIR metadata remains visible. |
| 2 | Attempt direct `INSERT`/`UPDATE`/`DELETE` as ordinary or company-owner users | Denied — INSERT raises `42501`; UPDATE/DELETE match zero rows under RLS. |
| 3 | Call `fn_bir_form_upsert`/`fn_bir_form_mapping_upsert` as a non-maintainer (including a company owner) | Raises `42501`; company membership confers no global-config authority. |
| 4 | Call the governed RPCs as a provisioned `bir_config_maintainers` user | Create/update/delete succeed; each writes a `sys_audit_logs` row with old/new values, actor, action, and `_change_reason`. |
| 5 | Re-upsert the same `form_number`; attempt a direct table write as the maintainer | Re-upsert updates in place (no duplicate); direct table write is still blocked (RPC is the only write path). |
| 6 | Upsert a mapping against a non-existent form | Raises `23503` and leaves no row and no audit entry (atomic rollback). |

## GOVERNED-TAX-REFERENCE-001 - Governed Tax-Reference Write Policy (MDP-01)

Status: Executed Passing (2026-07-20) in `supabase/tests/060_mdp01_tax_reference_governance_test.sql`, 21 assertions after a clean `supabase db reset` replay including migration `20260721000001_mdp01_tax_reference_write_governance.sql`. Related finding: PXL-AUD-068.

Scenario: global `tax_codes`, `vat_codes`, and `atc_codes` are read-only for ordinary users, and all mutations flow through governed SECURITY DEFINER RPCs (authority = any company admin OR a global maintainer) with the pre-existing audit trigger, without regressing PXL-AUD-063.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Read the three tables as an ordinary authenticated user | Reads succeed. |
| 2 | Attempt direct INSERT/UPDATE as ordinary user, and direct INSERT/UPDATE as a company admin | Denied — INSERT raises `42501`; admin direct writes change nothing (RPC is the only path). |
| 3 | Call the governed RPCs as a non-admin non-maintainer | Raises `42501`. |
| 4 | Call the governed RPCs as a company admin and as a global maintainer | Create/update/set_active succeed; exactly one audit row per mutation (no double-logging), recording the acting user. |
| 5 | Upsert with an invalid tax_type | Raises `23514` and leaves no row and no audit entry (atomic rollback). |
| 6 | Exercise PXL-AUD-063 governance as an ordinary user | Still denied — the reused BIR governance surface is intact. |

## MASTER-DATA-AUDIT-COVERAGE-001 - Master-Data Audit Coverage (MDP-02)

Status: Executed Passing (2026-07-21) in `supabase/tests/061_mdp02_master_data_audit_coverage_test.sql`, 26 assertions after a clean `supabase db reset` replay including migration `20260721000004_mdp02_master_data_audit_coverage.sql`. Related gap: MD-30.

Scenario: the three previously uncovered company-scoped reference/config masters — `units_of_measure`, `item_categories`, and `percentage_tax_codes` — are brought under the existing `fn_audit_trigger`, capturing every insert/update/delete in `sys_audit_logs` without duplicating existing mechanisms or double-logging the MDP-01/PXL-AUD-063 RPC-audited global tables.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Insert a row in each master as a company admin | Exactly one `sys_audit_logs` row per insert with action `INSERT`, after-image, actor (`auth.uid()`), company context, and timestamp; no before-image and no fabricated `_change_reason`. |
| 2 | Update a row in each master | Exactly one additional audit row with action `UPDATE` capturing both before and after values. |
| 3 | Delete a row in each master | Exactly one audit row with action `DELETE`, the before-image, and a null after-image. |
| 4 | Insert then `ROLLBACK` to a savepoint | The audit row is visible before rollback and gone after — audit is atomic with the mutation (no orphan). |
| 5 | Inspect trigger catalog | Each of the three masters carries exactly one audit trigger; the RPC-audited global tables (`tax_codes`/`vat_codes`/`atc_codes`/`bir_forms`/`bir_form_mappings`) carry none (no double-logging). |

## MASTER-DATA-ACCESS-SOD-001 - Master-Data Access Control & SOD Foundation (MDP-03)

Status: Executed Passing (2026-07-22) in `supabase/tests/072_mdp03_master_data_access_sod_test.sql`, 35 assertions after a clean `supabase db reset` replay including migration `20260722000007_mdp03_master_data_access_sod.sql`. Related gaps: MD-27, MD-28.

Scenario: reusable master-data authorization foundation over the existing `user_company_memberships` model. Adds action-level master-data permissions, role mappings for current roles, future custom role-code compatibility, advisory SoD conflicts, optional branch scopes, branch-aware RLS/export filtering, and audit coverage for membership, permission, SoD, and branch-scope changes. No UI, authentication redesign, transaction workflow change, or posting behavior change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect permission catalog | Each registered master exposes view/create/edit/delete/import/export/approve definitions; unavailable deletes remain unavailable where no prior delete policy existed. |
| 2 | Inspect role mappings | Owner/admin retain all master-data authority; member keeps operational create/edit only; viewer remains read/export-only. |
| 3 | Use a custom role code mapped to project permissions | The existing membership table accepts the code and `fn_can_master_data_permission` honors the mapping without a parallel membership system. |
| 4 | Call legacy `fn_can_perform(..., 'master_data', table)` | Existing customer maintenance behavior is preserved; COA setup maintenance is denied to members through the new catalog. |
| 5 | Write through direct RLS as member/admin/viewer | Member can create an operational customer but not COA; admin can create COA; viewer cannot create customer; member cannot delete customer while admin can. |
| 6 | Grant optional branch scopes | Admin can grant scopes; scoped users see/export only allowed branch-aware masters; no-scope behavior remains company-wide. |
| 7 | Create branch-aware project rows | Scoped member can create in an allowed branch and is rejected (`42501`) in an unscoped branch; branch-filtered export returns only scoped rows. |
| 8 | Inspect SoD/audit evidence | Advisory create/edit/delete/import-vs-approve conflicts are visible for admin; member has none because approve is not assigned; membership and branch-scope grants are audited. |
| 9 | Export as global reader/non-member | Global read-only references remain exportable; non-members cannot export company masters. |

## COA-ENRICHMENT-001 - Chart of Accounts Enrichment (MDP-04)

Status: Executed Passing (2026-07-21) in `supabase/tests/062_mdp04_coa_enrichment_test.sql`, 23 assertions after a clean `supabase db reset` replay including migration `20260721000005_mdp04_coa_enrichment.sql`. Related gaps: MD-09, MD-10, MD-11, MD-12, MD-13.

Scenario: `chart_of_accounts` is enriched with financial-statement classification (generated `fs_statement`, `fs_group`/`fs_subgroup`), control-account/subledger governance reconciled with `company_accounting_config`, cash-flow classification, cost/tax flags, and an effective-date window — all additively, preserving existing hierarchy, posting-vs-header behaviour, and audit coverage.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Insert accounts of each type | `fs_statement` is generated (asset/liability/equity → balance_sheet; revenue/expense → income_statement); `fs_group` and P&L `cash_flow_category` auto-default while explicit values are preserved. |
| 2 | Call `fn_sync_coa_control_accounts(company)` | The AR/AP/cash/tax accounts named in `company_accounting_config` are flagged `is_control_account`/`allow_subledger` with the correct `subledger_type`; tax accounts are flagged `is_tax_account`; non-configured accounts are untouched. |
| 3 | Group accounts by `fs_statement` | Accounts roll up into balance-sheet and income-statement groups for reporting. |
| 4 | Inspect hierarchy and posting flags | Header accounts remain non-postable with child accounts under `parent_id`; detail accounts remain postable (posting logic preserved). |
| 5 | Write invalid `fs_group`/`subledger_type`/`cash_flow_category`, or `effective_to` < `effective_from` | Rejected by CHECK constraint (`23514`); a valid effective window is accepted. |
| 6 | Insert a legacy-shaped account (no new columns) and edit a classification field | Insert still succeeds (backward compatible); the edit is captured in `sys_audit_logs` (MDP-02 coverage intact). |

## COMPANY-SETUP-DEFAULTS-001 - Company Setup Defaults & Seed Templates (MDP-05)

Status: Executed Passing (2026-07-21) in `supabase/tests/063_mdp05_company_setup_defaults_test.sql`, 25 assertions after a clean `supabase db reset` replay including migration `20260721000006_mdp05_company_setup_defaults.sql`. Related gaps: MD-01, MD-04 (default UOM), MD-05.

Scenario: reusable backend seed capabilities let a company start with a usable Philippine COA, UOM set, and percentage-tax codes — via global read-only `coa_templates`/`coa_template_lines` and admin-gated `SECURITY DEFINER` seed functions, without a wizard, UX, or company-creation change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | `fn_seed_company_coa(company)` with default template selection | Resolves the PH_STANDARD template from `entity_type` and seeds a balanced, classified COA (all five types, generated `fs_statement`, header non-postable, parent hierarchy resolved, control/tax flags inherited). |
| 2 | Call the seed functions twice | Idempotent — re-seeding COA/UOM/PT inserts no duplicates. |
| 3 | Seed company A, inspect company B | Company isolation preserved — B is untouched. |
| 4 | `fn_seed_company_uom` / `fn_seed_company_percentage_tax_codes` | Standard UOM set and the PT-3 percentage-tax code are seeded; re-seeding inserts nothing. |
| 5 | Seed inside a savepoint, then roll back | The seeded COA is removed (atomic rollback). |
| 6 | Seed as a non-admin member | Rejected (`42501`); seed functions self-check `can_admin_company`. |
| 7 | Inspect classification and audit trail | Seeded accounts carry MDP-04 classification; seed inserts are captured in `sys_audit_logs` (MDP-02 provenance). |

## FISCAL-SERIES-PROVISIONING-001 - Fiscal Calendar & Number Series Auto-Provisioning (MDP-06)

Status: Executed Passing (2026-07-21) in `supabase/tests/064_mdp06_fiscal_series_provisioning_test.sql`, 24 assertions after a clean `supabase db reset` replay including migration `20260721000007_mdp06_fiscal_series_provisioning.sql`. Related gaps: MD-02, MD-03.

Scenario: reusable admin-gated backend functions provision a company's fiscal calendar and default document numbering — `fn_create_fiscal_year` (configurable start + 12 monthly periods), `fn_generate_fiscal_periods`, and `fn_provision_number_series` (per BIR-registered document type, branch-aware) — without a wizard, UI, posting-period validation, or numbering-engine change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | `fn_create_fiscal_year(company, '2026-01-01')` | Creates a calendar fiscal year (ends Dec 31) and generates 12 open monthly periods spanning Jan–Dec. |
| 2 | `fn_create_fiscal_year(company, '2026-07-01')` | Creates a non-calendar fiscal year (ends Jun 30) with periods starting on the configured date. |
| 3 | Re-run creation / period generation | Idempotent — same fiscal-year id returned, no duplicate periods. |
| 4 | `fn_provision_number_series(company, branch)` | Provisions one series per BIR-registered document type (SI/CS/OR) with a sane default shape; a second branch gets its own series; re-running creates no duplicates. |
| 5 | Provision company A, inspect company B | Company isolation preserved. |
| 6 | Provision inside a savepoint, then roll back | Fiscal year and periods removed (atomic). |
| 7 | Provision as a non-admin member | Rejected (`42501`). |
| 8 | Inspect audit trail | Fiscal year, periods, and series creation captured in `sys_audit_logs` (fiscal-table audit added here; number_series already covered). |

## COMPANY-CONFIG-PROVISIONING-001 - Company Accounting & Compliance Configuration Provisioning (MDP-07)

Status: Executed Passing (2026-07-22) in `supabase/tests/065_mdp07_company_config_compliance_test.sql`, 24 assertions after a clean `supabase db reset` replay including migration `20260721000008_mdp07_company_config_compliance_currency.sql`. Related gaps: MD-06, MD-07, MD-31.

Scenario: reusable admin-gated backend functions provision and validate a company's accounting config, compliance profile, and explicit functional/reporting currency — `fn_provision_company_accounting_config` (idempotent create + control-account mapping from the company COA by canonical code, fill-NULL-only, reusing MDP-04 `fn_sync_coa_control_accounts`), `fn_validate_company_accounting_config`, and `fn_provision_compliance_profile` (derived from `companies.tax_registration`) — without a wizard, UI, posting-logic, or tax-calculation change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect a new company's currency | Defaults to PHP functional and reporting currency; an invalid currency code is rejected by the `currencies` FK (`23503`). |
| 2 | `fn_provision_company_accounting_config(company)` | Creates the config row and maps AR/cash/output-VAT/CWT/AP/input-VAT/EWT-payable accounts from the company COA by canonical code. |
| 3 | Re-run provisioning | Idempotent — same config id, no duplicate row; a manually mapped account is preserved (fills NULLs only). |
| 4 | `fn_validate_company_accounting_config(company)` | Clean config returns no problems; wrong-type, cross-company, and missing-config mappings are each flagged. |
| 5 | Inspect COA control flags / audit trail | Mapped AR account is flagged as a control account (sync ran); config creation is captured in `sys_audit_logs` (MDP-02 deferral completed). |
| 6 | `fn_provision_compliance_profile(company)` | A VAT company gets a VAT-registered quarterly profile; a non-VAT company gets a percentage-tax 3% profile; the tax calendar is regenerated (existing trigger). |
| 7 | Provision company A, inspect company B | Company isolation preserved; provisioning inside a savepoint rolls back atomically. |
| 8 | Provision/validate as a non-admin member | Rejected (`42501`); all functions self-check `can_admin_company`. |

## DIMENSION-MASTERS-001 - Dimension Masters: Project, Location, Functional Entity (MDP-09)

Status: Executed Passing (2026-07-22) in `supabase/tests/066_mdp09_dimension_masters_test.sql`, 32 assertions after a clean `supabase db reset` replay including migration `20260722000001_mdp09_dimension_masters.sql`. Related gaps: MD-14, MD-15, MD-16.

Scenario: three governed company-scoped analytical-dimension masters — `projects`, `locations`, `functional_entities` — each branch-aware, self-referencing hierarchical, effective-dated, and `is_active`-lifecycled, with member-gated RLS, audit coverage, a reusable side-effect-free `fn_is_valid_dimension` checker for future transaction packages, and admin-gated default provisioning — without any UI, transaction-form, posting, or report change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Create parent + child of each master | CRUD works; codes are unique within a company (`23505` on duplicate). |
| 2 | Set a self-parent / a cycle / a cross-company parent | Each rejected by `fn_dimension_hierarchy_guard` (`23514`). |
| 3 | Insert with `valid_to` before `valid_from` / unknown `branch_id` | Effective-window CHECK (`23514`); branch FK (`23503`). |
| 4 | `fn_is_valid_dimension(type,id,company,branch,as_of)` | True for an active in-window same-company dimension; false for a different company, an inactive row, an out-of-window date, or a mismatched branch; NULL id is valid; an unknown type raises (`22023`). |
| 5 | Read as an admin of another company | RLS scopes reads to the caller's companies (isolation). |
| 6 | `fn_provision_company_dimension_defaults(company)` twice | Idempotently scaffolds a Head Office location + a General functional entity; admin-gated. |
| 7 | Inspect audit trail; provision inside a savepoint then roll back | Creation captured in `sys_audit_logs`; rollback removes the row (atomic). |
| 8 | Write as a non-member / member / non-admin | Non-member insert rejected (`42501`); a member can insert; default provisioning is admin-only (`42501`). |

## PARTY-MASTERS-ENRICHMENT-001 - Party Masters Enrichment: Groups, Contacts, TIN Control (MDP-10)

Status: Executed Passing (2026-07-22) in `supabase/tests/067_mdp10_party_masters_enrichment_test.sql`, 30 assertions after a clean `supabase db reset` replay including migration `20260722000002_mdp10_party_masters_enrichment.sql`. Related gaps: MD-17, MD-18, MD-19.

Scenario: governed company-scoped `customer_groups`/`supplier_groups` masters (legacy free-text `*_group` preserved as fallback and backfilled), a `party_contacts` multi-contact master (a contact belongs to a customer XOR a supplier, at most one primary per party, company-isolation guard), and side-effect-free `fn_party_tin_duplicates` detection — without any UI, transaction-form, posting, or tax change. Note: Philippine TIN normalization and the canonical `XXX-XXX-XXX-XXXXX` format already exist, so MD-19 is duplicate detection only (no hard unique — legitimate branch/dual-role duplicates exist).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Link a customer to a governed group; inspect the legacy column | The `customer_group_id` FK resolves to the group name; the legacy free-text `customer_group` is preserved (non-destructive). |
| 2 | Insert a duplicate `group_code` in a company | Rejected (`23505`); group codes are unique per company. |
| 3 | Add multiple contacts to one party; add a second primary | Multiple contacts allowed; a second primary is rejected by the partial unique index (`23505`). |
| 4 | Insert a contact with both/neither party, or a mismatched company | Both/neither rejected by the XOR CHECK (`23514`); a company mismatch rejected by the isolation guard (`23514`). |
| 5 | `fn_party_tin_duplicates(company, type, tin, exclude)` | Finds same-company, same-type parties sharing a normalized TIN; honors the exclusion id; is company- and party-type-scoped; normalizes the input; an unknown type raises (`22023`). |
| 6 | Inspect stored party TIN; toggle a group inactive | TIN is stored canonical `XXX-XXX-XXX-XXXXX` (regression); groups support active/inactive lifecycle. |
| 7 | Inspect audit trail; insert inside a savepoint then roll back | Group and contact creation captured in `sys_audit_logs`; rollback removes the row (atomic). |
| 8 | Read/write as member of A vs non-member | A member of A cannot see Company B rows (RLS isolation); a member can create; a non-member is rejected (`42501`). |

## ATTRIBUTION-REFERENCE-MASTERS-001 - Attribution & Reference Masters: Salesperson, Bank, Payment Modes (MDP-11)

Status: Executed Passing (2026-07-22) in `supabase/tests/068_mdp11_attribution_reference_masters_test.sql`, 28 assertions after a clean `supabase db reset` replay including migration `20260722000003_mdp11_attribution_reference_masters.sql`. Related gaps: MD-20, MD-25, MD-26.

Scenario: governed salesperson/buyer **designation** on the `employees` master (`is_salesperson`/`is_buyer` + reusable `fn_is_valid_attribution`, reusing the existing `sales_invoices.salesperson_id` FK, not a duplicate table); a global read-only `ref_banks` reference master with an additive `bank_accounts.bank_id` link (legacy `bank_name` preserved); and company-scoped `company_payment_modes` mapping a global `ref_payment_modes` entry to a postable same-company GL account — reference masters only, no posting/tax/banking/AR-AP redesign.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Flag employees; `fn_is_valid_attribution(kind, employee, company)` | True for an active designated salesperson/buyer of the company; false for a different company, an undesignated or inactive employee; NULL employee is valid; an unknown kind raises (`22023`). |
| 2 | Inspect `ref_banks`; insert as an authenticated user | Seeded with PH banks; read-only (deny-by-default writes, `42501`). |
| 3 | Link a bank account via `bank_id`; inspect `bank_name` | `bank_id` resolves to the `ref_banks` name; the legacy free-text `bank_name` is preserved; an unknown `bank_id` is rejected (`23503`). |
| 4 | Create a `company_payment_modes` row; map a cross-company / non-postable GL account | Valid same-company postable mapping succeeds; cross-company and non-postable GL accounts are rejected by `fn_company_payment_mode_gl_guard` (`23514`); a mode is unique per company (`23505`). |
| 5 | Toggle a mode inactive; inspect audit trail | Active/inactive lifecycle works; creation captured in `sys_audit_logs`. |
| 6 | Insert inside a savepoint then roll back | Rollback removes the row (atomic). |
| 7 | Read/write as member of A vs member-of-A-only vs non-member | Company B rows are invisible to a member of A (RLS isolation); a member can create; a non-member's write is rejected. |

## TAX-REFERENCE-CONSOLIDATION-001 - Tax Reference Consolidation (MDP-12)

Status: Executed Passing (2026-07-22) in `supabase/tests/069_mdp12_tax_reference_consolidation_test.sql`, 16 assertions after a clean `supabase db reset` replay including migration `20260722000004_mdp12_tax_reference_consolidation.sql`. Related gap: MD-32.

Scenario: MD-32 (two parallel ATC representations) was already resolved by prior work — `ref_atc_codes` was dropped with its FKs repointed to `atc_codes`, and `ewt_codes`/`fwt_codes` were consolidated away — so `atc_codes` is the single authoritative ATC source and `tax_codes`/`vat_codes`/`atc_codes` already share one versioning/effective-dating/governance pattern. This package adds only a thin read-only consolidation surface and locks the invariants; no tax-engine, posting, or governance change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Check `ref_atc_codes` / `ewt_codes` / `fwt_codes` | All dropped (`to_regclass` NULL) — consolidation complete. |
| 2 | Inspect `receipt_lines.atc_code_id` FK | Targets `atc_codes` (former `ref_atc_codes` FK repointed). |
| 3 | Query `vw_tax_reference_catalog` | Exposes both `tax_code` and `atc_code` references with a computed `is_current`; readable by an authenticated user (security_invoker). |
| 4 | `fn_tax_reference_asof(reference_type, code, tax_category, as_of)` | Delegates to `fn_tax_code_version_asof` / `fn_atc_version_asof`; normalizes the code (case-insensitive); returns NULL for a non-resolving code; missing ATC `tax_category` and an unknown reference type each raise (`22023`). |
| 5 | Insert into `atc_codes` / `tax_codes` as an authenticated user | Rejected (`42501`) — the masters remain MDP-01 read-only (governed writes only). |

## ITEM-MASTER-INVENTORY-READINESS-001 - Item Master Inventory Readiness (MDP-13)

Status: Executed Passing (2026-07-22) in `supabase/tests/070_mdp13_item_master_inventory_readiness_test.sql`, 41 assertions after a clean `supabase db reset` replay including migration `20260722000005_mdp13_item_master_inventory_readiness.sql`. Related gaps: MD-21, MD-22, MD-23, MD-24.

Scenario: backend/master-data readiness for Phase 4 Inventory — company inventory defaults (costing method, negative-stock policy, default warehouse) with provision/validate/guard; item-level overrides + reorder fields + preferred supplier + serial/batch flags with never-NULL effective-policy resolvers; per-item UOM conversions; item barcodes and media. No inventory movement, valuation, costing engine, UI, or posting change.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | `fn_provision_company_inventory_config(company)` | Creates `company_inventory_config` with defaults (weighted_average / block) and the company's active warehouse; idempotent; a cross-company default warehouse is rejected (`23514`); `fn_validate_company_inventory_config` reports `config_missing` / bad warehouse; provisioning is admin-only (`42501`). |
| 2 | `fn_item_costing_method` / `fn_item_negative_stock_policy` | Resolve item override → company default → literal (`weighted_average` / `block`); never NULL; reflect item and company changes. |
| 3 | Update item fields | `negative_stock_policy` vocabulary and non-negative reorder fields are enforced (`23514`); `preferred_supplier_id` must be same-company (`23514`). |
| 4 | Insert `item_uom_conversions` | Stored; one conversion per UOM per item (`23505`); factor must be > 0 (`23514`); a cross-company UOM is rejected and `company_id` is derived from the item by the child guard. |
| 5 | Insert `item_barcodes` / `item_media` | Stored; at most one primary per item (`23505`); barcodes unique per company (`23505`). |
| 6 | Inspect audit trail; insert inside a savepoint then roll back | Config/barcode/UOM-conversion creation captured in `sys_audit_logs`; rollback removes the row (atomic). |
| 7 | Write as a member vs a non-member | A company member can add item children; a non-member cannot. |

## MASTER-DATA-IMPORT-EXPORT-001 - Master-Data Import / Export Foundation (MDP-15)

Status: Executed Passing (2026-07-22) in `supabase/tests/071_mdp15_master_data_import_export_test.sql`, 38 assertions after a clean `supabase db reset` replay including migration `20260722000006_mdp15_master_data_import_export.sql`. Related gaps: MD-34, MD-35.

Scenario: backend-first master-data import/export foundation for current completed master-data packages. Adds a supported-master registry, import templates, deterministic JSON export with SHA-256 export logs, validation/preview/import RPCs, idempotency keys, row-level errors, company isolation, operation audit logs, and rollback-safe commit handling. Global statutory tax/BIR references remain exportable but not tenant-importable through this generic path; their existing MDP-01/PXL-AUD-063 governed RPCs stay authoritative.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect `master_data_import_registry` and templates | Current master surfaces are registered with scope/import mode; COA template exposes `account_code` as the business key and excludes generated columns. |
| 2 | Validate import for `tax_codes` | Returns deterministic `master_not_importable`; global statutory references remain governed elsewhere. |
| 3 | Preview a valid `branches` payload | Returns `validated`, writes a preview batch/row record, and leaves the `branches` table unchanged. |
| 4 | Validate duplicate, missing-required, missing-FK, and cross-company rows | Row-level errors report `duplicate_source_key`, `required_column_missing`, `missing_reference`, and `company_scope_mismatch`. |
| 5 | Commit a valid branch import and replay the same idempotency key | First call inserts one branch; replay returns the prior batch and does not duplicate; reusing the key with a different payload is rejected. |
| 6 | Commit an update matched by business key | Existing branch updates deterministically and the batch records `updated_count`. |
| 7 | Commit a row that passes prevalidation but fails a DB CHECK | Import returns failed status and no partial master row persists. |
| 8 | Export another company's master data as a non-member | Export is rejected (`42501`), preserving company isolation. |
| 9 | Import hierarchical COA rows with child before parent | Commit succeeds after dependency-aware ordering; parent reference is preserved. |
| 10 | Export branch and package payloads | Exports return deterministic row counts, content SHA-256, and matching `master_data_export_logs`; package export includes company masters in registry order. |
| 11 | Inspect audit trail | Import/export operation metadata is captured in `sys_audit_logs`; underlying imported branch mutation is captured by the branch audit trigger. |

## GUIDED-COMPANY-PROVISIONING-001 - Guided Company Provisioning (MDP-08)

Status: Executed Passing (2026-07-22) in `supabase/tests/073_mdp08_guided_company_provisioning_test.sql`, 50 assertions after a clean `supabase db reset --local --no-seed` replay including migration `20260722000008_mdp08_guided_company_provisioning.sql`. Current full pgTAP regression passed 74 files / 1,568 assertions after MDP-14. Related gap: MD-08.

Scenario: a versioned company template composes the completed provisioning primitives behind one permission-gated, deterministic, atomic, and idempotent RPC. PH_STANDARD creates legal identity, owner membership, default branch/warehouse, fiscal year and 12 periods, number series, 41-account COA, UOM/tax defaults, all current accounting-control mappings, compliance profile, dimensions, inventory configuration, and a company payment mode. Failed business setup rolls back while the audited run retains deterministic failure metadata.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect current PH_STANDARD template and module composition | One active current template exposes localization/currency defaults and ten ordered required modules with valid handlers. |
| 2 | Validate a complete request | Side-effect-free validation returns no errors and creates no company or provisioning-run row. |
| 3 | Provision as the zero-company bootstrap user / existing owner | Authorized caller succeeds; ordinary member and outsider are rejected (`42501`). |
| 4 | Inspect provisioned company and ownership | Company code/TIN/legal/fiscal/currency fields persist; creator has owner membership. |
| 5 | Inspect branch, warehouse, fiscal calendar, series, and defaults | One default branch/warehouse, one fiscal year with 12 periods, required BIR number series, UOM/PT defaults, and standard dimensions exist. |
| 6 | Inspect COA and accounting configuration | All 41 hierarchical PH_STANDARD accounts exist; nine accounting mappings resolve to same-company postable accounts, including Customer Advances (liability) and Supplier Down Payments (asset). |
| 7 | Inspect compliance, inventory, and payment mode | Compliance/tax calendar, company inventory default warehouse, and CASH payment-mode mapping are complete. |
| 8 | Replay the same request/key | Returns the prior successful result with `idempotent_replay = true`; no business rows duplicate. Reusing a key for changed input is rejected. |
| 9 | Validate duplicate company code/TIN, invalid fiscal/template/reference inputs | Deterministic ordered field errors are returned and no company is created. |
| 10 | Force a required extension module to fail inside the orchestration subtransaction | Company and all dependent business rows roll back; the run is retained as failed with error evidence. |
| 11 | Inspect direct table policy and internal handlers | Authorized provisioning-compatible direct company inserts remain possible for backward compatibility; unauthorized inserts fail; internal module handlers are not executable by `authenticated`. |
| 12 | Inspect audit evidence and RLS | Company creation and provisioning execution/completion are auditable; users can read only runs for companies they administer. |

## APPROVAL-MATRIX-INTEGRATION-001 - Approval Matrix Integration (MDP-14)

Status: Executed Passing (2026-07-22) in `supabase/tests/074_mdp14_approval_matrix_integration_test.sql`, 61 assertions after a clean `supabase db reset --local --no-seed` replay including migration `20260722000009_mdp14_approval_matrix_integration.sql`; a direct second migration replay with `ON_ERROR_STOP=1` also passed. Targeted tests 011/014/050/071/072/073 passed 171/171 and the full pgTAP lane passed 74 files / 1,568 assertions. Related gap: MD-33.

Scenario: configuration-first extension of the existing approval workflow, step, and instance architecture. Rules resolve deterministically from company, optional branch, module/record, action, amount, currency, requester context, effective dates, and active state. A version-bound `approval_requests` header and RPC-only lifecycle provide multi-level role/user routing, current-step locking, requester separation, MDP-03 permission/branch/SOD enforcement, inactive/missing-approver validation, stale/duplicate/repeated transition protection, MDP-02 audit evidence, and an inbox/status API. No rules are seeded. The bounded Master Data consumer is a configured MDP-15 import commit; previews and unconfigured commits remain compatible.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Create company/fallback/branch/effective rules and role/user steps | Admin configuration succeeds; non-admin maintenance is denied; tenant RLS hides another company's rules. |
| 2 | Resolve branch-specific, fallback, future, and absent rules | Most-specific valid rule wins; fallback is deterministic; effective boundaries are exact; absent rules return `not_required`. |
| 3 | Resolve a route with a deleted user | Decision reports no valid approver and submission fails closed. |
| 4 | Preview then submit a configured department import | Preview validates without mutation; submission is permission-gated, version-bound, and duplicate-idempotent; commit before approval is denied. |
| 5 | Attempt self, viewer, wrong-role, enforced-conflict, and wrong-branch decisions | Each is denied server-side; advisory SOD does not block a different valid approver. |
| 6 | Complete two approval levels | First decision yields `partially_approved` and activates only the next step; second yields `approved`; ordered history contains both actors. |
| 7 | Repeat or concurrently contend for an actionable transition | Request/current-instance row locks, status guards, and the actionable-source unique index prevent double action and duplicate pending requests. |
| 8 | Commit and replay the approved import | Exact payload hash and request identity are revalidated; success consumes the request; the same MDP-15 idempotency key replays without duplicate data. |
| 9 | Reject, withdraw, and attempt invalid follow-up transitions | Rejection requires a reason; requester/admin withdrawal closes pending steps; closed requests cannot be approved. |
| 10 | Approve with a changed record version and resubmit | Stale request becomes `superseded`; changed source version produces a distinct current request. |
| 11 | Inspect audit and direct-write boundaries | Rules, requests, resolution instances, and decisions appear in `sys_audit_logs`; authenticated direct instance mutation is denied. |
| 12 | Run MDP-03, MDP-08, MDP-15, legacy approval, and full regressions | Existing permission/SOD, provisioning, import/export, DEC-010 approval, accounting readiness, and all prior pgTAP behavior remain green. |

## TABLE-COVERAGE-GOVERNANCE-001 - Coverage Governance (PXL-AUD-059)

Status: Executed Passing (2026-07-22) in `supabase/tests/075_table_coverage_governance_test.sql`. Canonical lane (fresh replay + reset/base/enrichment/volume seed) passed 4 files / 96 assertions including 075 at 8/8; full pgTAP regression passed 75 files / 1,596 assertions with 075 exercising its structural no-seed branch. Governs the maintained matrix `docs/PXL/13. Testing and Validation/PXL_TABLE_COVERAGE_MATRIX.md`.

Scenario: every `public` base table is classified into exactly one coverage class — `canonical-populated` (66), `reference-populated` (24), `workflow-deferred` (19), `future-deferred` (61), or `reference-empty` (6). The guard fails on unexpected active-table emptiness and on governance drift, but never merely because an intentionally deferred module is empty. Structural checks run in every lane; seed-gated population checks run in the canonical lane.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Compare `information_schema` base tables to the registry | Every public base table is classified; no unclassified table remains. |
| 2 | Compare the registry to `information_schema` | No stale registry entry maps to a missing table. |
| 3 | Validate each registry class value | Only the five governed coverage classes are used. |
| 4 | Count `reference-populated` tables (any lane) | All retain their migration/reference seed rows. |
| 5 | Count `canonical-populated` tables (canonical lane) | All are non-empty — no unexpected active-table emptiness. |
| 6 | Count `workflow-deferred`, `future-deferred`, `reference-empty` (canonical lane) | All remain intentionally empty until their workflow is exercised. |
| 7 | Run without the canonical seed | Structural checks pass; population checks skip deterministically. |

## REPORTING-VIEW-TENANT-ISOLATION-001 - Reporting-view RLS isolation (PXL-AUD-069)

Status: Executed Passing (2026-07-22) in `supabase/tests/076_reporting_view_tenant_isolation_test.sql`, 6 assertions after a clean `supabase db reset --local --no-seed` replay including migration `20260722000011_aud069_reporting_view_rls_isolation.sql`. Empirically confirmed the pre-fix leak (a member of one company read another company's payment register/AP aging/receipt register/SLP export) and that it is closed after the fix while legitimate own-company access is preserved.

Scenario: three companies (A, B, C) each with a distinct member; one payment voucher seeded in company A. Through the now-`security_invoker` `vw_payment_register`, the member of A reads exactly A's row (and only company A), while the member of B and a non-member of A read zero of A's rows. All nine remediated reporting views (`vw_ap_aging`, `vw_credit_memo_register`, `vw_debit_memo_register`, `vw_deposits_in_transit`, `vw_outstanding_checks`, `vw_payment_register`, `vw_receipt_register`, `vw_sdm_register`, `vw_slp_export`) are asserted to carry `security_invoker`, extending the proven mechanism to every view.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Member of company A reads `vw_payment_register` | Sees own-company voucher; only company A is visible. |
| 2 | Member of company B reads the same view | Cannot see company A's voucher (zero rows). |
| 3 | Non-member of company A reads the view | Receives zero company-A rows. |
| 4 | Inspect all nine remediated views | Every view carries `security_invoker`; none remains RLS-bypassing. |

## REPORTING-VIEW-SECURITY-GUARD-001 - Permanent view-isolation guard (PXL-AUD-069)

Status: Executed Passing (2026-07-22) in `supabase/tests/077_reporting_view_security_guard_test.sql`, 2 assertions, run in every regression and canonical lane. Proven non-vacuous: temporarily resetting `security_invoker` on one view makes the guard fail and name the offending view; restoring it passes.

Scenario: the guard scans `pg_catalog` for any public view that is granted SELECT to `authenticated`, is owned by an RLS-bypassing (superuser/BYPASSRLS) role, is not `security_invoker`, and embeds no tenant-isolation predicate (`is_company_member` / `user_company_memberships` / `auth.uid` / `can_admin_company`). The set must be empty; a new authenticated view without isolation fails the build.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Enumerate RLS-bypassing authenticated views without isolation | The set is empty (count 0). |
| 2 | Report the offending-view list | The list is `(none)`. |

## IMMUTABILITY-BYPASS-GUARD-001 - Posted-document immutability cannot be disabled by a user GUC (PXL-AUD-070)

Status: Executed Passing (2026-07-23) in `supabase/tests/078_immutability_demo_reset_bypass_guard_test.sql`, 16 assertions, run in every regression and canonical lane. The production-identical attack (a real `authenticator` connection → `SET ROLE authenticated` as a company member → `SET pxl.allow_demo_reset = 'on'`) is recorded in PXL-AUD-070: the member sees the posted voucher through RLS, but `fn_demo_reset_bypass_authorized()` returns false and every UPDATE/DELETE against the posted document and its lines is blocked.

Scenario: a committed posted check voucher is provisioned. With the bypass GUC off, direct-SQL UPDATE/DELETE of the posted header and line are rejected as immutable. The privileged-role classifier `fn_role_is_privileged_maintenance` returns false for `authenticated`/`authenticator`/`anon` and true only for `postgres`/`service_role`; the composite gate `fn_demo_reset_bypass_authorized()` is false with the GUC off, true only for a privileged `session_user` with the GUC on, and never authorized for a PostgREST role even with the GUC on. The authorized maintenance path (privileged `session_user` + GUC on) still rewrites a posted document. A permanent static guard fails the build if any function reads `pxl.allow_demo_reset` for a bypass without routing through the privileged gate, if any of the six immutability guard functions stops routing through it, or if the gate/classifier stops keying off `session_user`/`rolsuper`/`rolbypassrls`.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Direct-SQL UPDATE/DELETE a posted check voucher and its line (GUC off) | All rejected as immutable / cannot be changed. |
| 2 | Classify `authenticated`/`authenticator`/`anon` vs `postgres`/`service_role` | Untrusted roles are not privileged; maintenance roles are. |
| 3 | Evaluate the bypass gate with the GUC off, then on | False with the GUC off; true only for a privileged `session_user` with the GUC on. |
| 4 | Confirm the GUC alone never authorizes a PostgREST session | No authenticator/authenticated/anon session is ever authorized. |
| 5 | Authorized maintenance context rewrites a posted document | Succeeds only under a privileged `session_user` with the GUC on. |
| 6 | Static guard over `pg_proc` | No naked GUC bypass; all six guards route through the privileged gate. |

## NUMBER-SERIES-ENGINE-001 - Number Series Engine certification regression

Status: Executed Passing (2026-07-23) in `supabase/tests/079_number_series_engine_certification_test.sql`, 17 assertions, run in every regression and canonical lane. Complements test 030 (registry code consistency) and test 032 (SI/JE reservation, ATP exhaustion, immutable void evidence, no-backward/no-identity guards). Empirical concurrency — 10 concurrent clients × 20 allocations → 200 distinct, contiguous `JE-000001..JE-000200`, counter == 200, zero duplicates, zero errors — is recorded in the Number Series Engine certification evidence; the structural assertions here guard the mechanism (`FOR UPDATE` row lock plus the registry UNIQUE constraints) that makes it hold.

Scenario: a company with two branches and a JE series in each. A non-member cannot allocate; branch counters advance independently; a same-transaction rollback leaves the counter undrifted (no gap) and the number is reused; an inactive series cannot allocate; a manually-numbered document registers as issued evidence and a duplicate manual number is rejected; the contract guard rejects `has_dynamic_year = true` and `reset_frequency <> never` (the continuous allocator honors neither), accepts a default continuous series, and blocks backward counter movement and unsupported reconfiguration; an unconfigured document code fails closed; and the structural row-lock plus registry UNIQUE constraints are present.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Non-member calls the allocator | Rejected: Access denied. |
| 2 | Allocate in two branches | Independent per-branch sequences. |
| 3 | Allocate then rollback the transaction | Counter undrifted; number reused (no gap). |
| 4 | Allocate from an inactive series | Rejected: no active number series. |
| 5 | Insert a duplicate manual document number | Rejected: uniqueness cannot be bypassed. |
| 6 | Configure `has_dynamic_year`/`reset_frequency` | Rejected as unsupported; default continuous series accepted. |
| 7 | Inspect allocator + registry structure | `FOR UPDATE` lock and both registry UNIQUE constraints present. |

## DIM-ENGINE-CERT-001 - Dimension Engine certification regression

Status: Executed Passing (2026-07-23) in `supabase/tests/080_dimension_engine_certification_test.sql`, 43 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260723000003_dimension_engine_certification.sql`; full pgTAP regression passed 80 files / 1,680 assertions. Complements test 019 (branch/dept/cost-center JE-line propagation, branch P&L reconciliation) and test 066 (dimension masters, hierarchy, effective dating, `fn_is_valid_dimension`). Proves that every implemented, dimension-bearing posting transaction now carries all six governed dimensions (branch, department, cost_center, project, location, functional_entity) onto the posted journal lines, that reversal preserves them, that the dimensional GL report reconciles to the undimensioned control total without double counting, and that cross-company and hierarchy violations are rejected. The strengthened JE-line guard is proven non-vacuous: with `trg_je_line_dimensions_guard` disabled a cross-company project is accepted onto a company-A line; with it enabled the same insert is rejected.

Scenario: two companies each with a branch and a full dimension set. A Manual Journal posts all six dimensions onto its line and they surface in `vw_general_ledger` and `vw_gl_dimension_summary`; reversal via `fn_reverse_je` preserves all six. A Vendor Bill's dimensions inherit onto its posting line through `fn_add_posting_line`. A Goods Issue posts department/cost-center/project/location/functional-entity onto its GL lines and the inventory movement. A Fixed Asset acquisition and its first depreciation entry carry the dimensions onto every journal line. The JE-line guard rejects a cross-company branch/department/cost-center/project/location/functional-entity; a dimension master rejects self-parent and cross-company parent; and `fn_register_fixed_asset` rejects a cross-company project at source. The dimensional summary and the `fn_report_gl_by_dimension` drill-down for department, project, and functional entity each reconcile to the same GL control total.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Post a Manual Journal with all six dimensions | Every dimension persists on the journal line and in the GL views. |
| 2 | Reverse the manual journal | Reversal line preserves all six dimensions. |
| 3 | Add a Vendor Bill posting line via `fn_add_posting_line` | Line inherits department/cost-center/project/location/functional-entity from the bill. |
| 4 | Post a Goods Issue | GL lines and the inventory movement carry the dimensions. |
| 5 | Register a Fixed Asset and post depreciation | Acquisition and depreciation journal lines carry the dimensions. |
| 6 | Attach a cross-company dimension to a company-A line | Rejected: dimension does not belong to company. |
| 7 | Self-parent / cross-company parent on a dimension master | Rejected by the hierarchy guard. |
| 8 | Register a Fixed Asset with a cross-company project | Rejected: invalid project for Fixed Asset. |
| 9 | Sum the dimensional summary and each drill-down | Reconciles to the undimensioned GL control total (no double counting). |

## COA-ENGINE-CERT-001 - COA Engine (Phase A) certification + equivalence regression

Status: Pending first green run (added 2026-07-24) in `supabase/tests/081_coa_engine_certification_test.sql`, 45 assertions, to run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260724000001_coa_engine_phase_a.sql`. Governs the frozen COA Engine contract `docs/PXL/02. Accounting Core/PXL_COA_ENGINE_SPEC.md` (certifiable engine #19). Phase A is additive: it rewires no posting consumer, so it establishes the resolver + lifecycle + change-policy + FS-registry foundation and its equivalence to today's `company_accounting_config`, not full engine certification.

Scenario: one company provisions the canonical PXL Standard COA (33 accounts, full metadata, 8 FS lines, one active FS mapping per account). Its `company_accounting_config` is set; the sync trigger seeds the nine company-scope `account_mapping` bindings, and `fn_resolve_account` plus `vw_company_accounting_config` return exactly the configured accounts (equivalence). More-specific document-type and branch bindings prove deterministic precedence (document_type outranks branch outranks company default); two equal-specificity candidates are rejected as ambiguous rather than guessed. The resolver fails closed on no/unknown/inactive key and rejects a resolved account that is wrong-type, non-postable, or non-active; an authorized transaction override wins while an unauthorized one is rejected. Lifecycle transitions enforce the state graph and the zero-balance archive rule; the change-policy guard makes `account_type`/`normal_balance` immutable and blocks deletion once an account has posted history; posting-control validators enforce leaf/postable/manual-control rules; the FS registry keeps one active mapping per account per statement with effective-dated reclassification; and `authenticated` cannot write `account_mapping`, keeping the config the single writable authority.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Provision the canonical PXL Standard COA | 33 accounts with complete metadata + populated FS registry. |
| 2 | Set config; resolve each key | `fn_resolve_account` and the compat view equal the configured accounts. |
| 3 | Resolve with document_type / branch context | Most-specific binding wins; document_type outranks branch. |
| 4 | Resolve with two equal-specificity candidates | Rejected as ambiguous; never guessed. |
| 5 | Resolve missing / unknown / inactive key | Fails closed with a specific error. |
| 6 | Resolve to a wrong-type / non-postable / inactive account | Rejected by account validation. |
| 7 | Transition lifecycle (valid, invalid, archive non-zero) | State graph and zero-balance archive rule enforced. |
| 8 | Mutate / delete an account with posted history | `account_type`/`normal_balance` immutable; deletion blocked. |
| 9 | Insert a second active FS mapping; then reclassify by effective date | Second open mapping blocked; close-and-open reclassification allowed. |
| 10 | Write `account_mapping` as `authenticated` | Rejected; config remains the single writable authority. |

## POSTING-ENGINE-P1-001 - Posting Engine Phase P1 infrastructure (additive, inert)

Status: Pending first green run (added 2026-07-24) in `supabase/tests/082_posting_engine_p1_infra_test.sql`, 22 assertions, to run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260724000002_posting_engine_p1_infra.sql`. Governs the frozen Posting Engine architecture `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md` Phase P1 (infrastructure only, zero accounting behavior change). P1 is additive: it adds the Posting Context, Posting Plan validator/fingerprint, central Option-B journal-number derivation, additive metadata columns, and a push-based line builder ALONGSIDE the untouched legacy kernel — nothing is wired into existing posting, so existing journals remain byte-for-byte identical (proven by the full regression staying green).

Scenario: the six additive metadata columns (`posting_origin`, `reversal_of_je_id`, `posting_run_id`, `source_fingerprint`, `line_role`, `source_line_id`) exist and are nullable, with CHECK constraints rejecting invalid `posting_origin`/`line_role`. `fn_derive_journal_number` produces `JE-<TYPE>-<source#>` byte-identically for source-numbered documents, normalizes the type to uppercase, and fails closed for source-less journals without a company or a provisioned `JE` number series. `fn_build_posting_context` assembles the canonical context (uppercased source type, `as_of` defaulting to posting date, pushed dimensions). `fn_validate_posting_plan` accepts a balanced plan and rejects unbalanced / both-sided / missing-account / empty / missing-company plans. `fn_posting_plan_fingerprint` is deterministic for equal plans and differs for different ones. `fn_add_posting_line_push` inserts lines with caller-supplied dimensions, `line_role`, and `source_line_id` (no source-table pull). The legacy `fn_create_posted_journal_entry` and `fn_add_posting_line` remain present alongside the new builder (nothing removed).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect additive columns | Six nullable metadata columns exist; invalid `posting_origin`/`line_role` rejected by CHECK. |
| 2 | Derive a source-numbered journal number | `JE-<TYPE>-<source#>`, byte-identical to legacy; type uppercased. |
| 3 | Derive a source-less number without company / series | Fails closed. |
| 4 | Build a Posting Context | Canonical shape; uppercased type; `as_of` defaults; dimensions carried. |
| 5 | Validate posting plans | Balanced accepted; unbalanced/both-sided/missing-account/empty/missing-company rejected. |
| 6 | Fingerprint plans | Deterministic for equal plans; differs for different plans. |
| 7 | Push journal lines | Lines carry pushed dimensions, `line_role`, and `source_line_id`. |
| 8 | Inspect legacy builders | `fn_create_posted_journal_entry` and `fn_add_posting_line` remain alongside the push builder. |

## POSTING-ENGINE-P2A-001 - Sales resolver adoption (COA Engine Phase B, group 1)

Status: Pending first green run (added 2026-07-24) in `supabase/tests/083_posting_engine_p2a_sales_resolver_test.sql`, 11 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260724000003_posting_engine_p2a_sales_resolver.sql`. Certifies that the five Sales posting writers (`fn_post_sales_invoice`, `fn_post_receipt`, `fn_save_cash_sale`, `fn_post_credit_memo_vat_lump_impl`, `fn_post_debit_memo_vat_lump_impl`) resolve accounts exclusively through the certified COA resolver `fn_resolve_account` (via the `fn_resolve_posting_account` adapter) with no accounting behavior change. Byte-for-byte GL equality of real Sales postings is proven by the full regression + canonical lanes (test 001 critical flow, 054 SI completeness, canonical 055/057 post SI/OR/CM/DM/cash sale with exact GL assertions and remain green). Out of scope (unchanged): Vendor Bill, Cash Purchase, Vendor Credit, and every non-Sales writer.

Scenario: all five Sales writers reference `fn_resolve_posting_account` and none reads `company_accounting_config` for account resolution, while an out-of-scope reconciliation report (`fn_ap_subledger_gl_reconciliation_asof`) still reads config to identify control accounts (non-vacuous scope guard). The adapter returns the configured account for a resolvable key and re-raises the writer's friendly "not configured" message on a missing mapping. For a company with configured AR/Output VAT/Cash/CWT/Customer-Advances accounts, `fn_resolve_account` returns exactly those accounts (equivalence — the basis of GL equality). Every Sales writer populates `posting_origin` metadata.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect the five Sales writers | Each resolves via `fn_resolve_posting_account`; none reads `company_accounting_config`. |
| 2 | Inspect out-of-scope code | An out-of-scope reconciliation report still reads config (non-vacuous scope guard). |
| 3 | Resolve a configured key via the adapter | Returns the configured account. |
| 4 | Resolve a missing key via the adapter | Re-raises the friendly "not configured" message. |
| 5 | Compare resolver output to config | `fn_resolve_account` equals the configured AR/VAT/Cash/CWT/Advances accounts. |
| 6 | Inspect posting metadata | Every Sales writer populates `posting_origin`. |

## POSTING-ENGINE-P2B-001 - Purchasing resolver adoption (COA Engine Phase B, group 2)

Status: Pending first green run (added 2026-07-25) in `supabase/tests/084_posting_engine_p2b_purchasing_resolver_test.sql`, 11 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260724000004_posting_engine_p2b_purchasing_resolver.sql`. Certifies that the three Purchasing posting writers (`fn_post_vendor_bill`, `fn_post_cash_purchase_source_locked_impl`, `fn_post_vendor_credit_vat_lump_impl`) resolve accounts exclusively through the certified COA resolver `fn_resolve_account` (via the `fn_resolve_posting_account` adapter) with no accounting behavior change. Byte-for-byte GL equality of real Purchasing postings is proven by the full regression + canonical lanes (test 001 critical flow posts a Vendor Bill, 042 posts a Cash Purchase with EWT, 004/035 post a Vendor Credit, and canonical 055/057 post the purchasing families with exact GL assertions and remain green). Out of scope (unchanged): Sales (already P2A), Payment Voucher, Check Voucher, Withholding Remittance, Purchase Return, and every non-Purchasing writer.

Scenario: all three Purchasing writers reference `fn_resolve_posting_account` and none reads `company_accounting_config` for account resolution, while an out-of-scope reconciliation report (`fn_ap_subledger_gl_reconciliation_asof`) still reads config to identify control accounts (non-vacuous scope guard). The adapter returns the configured account for a resolvable key and re-raises the writer's friendly "not configured" message on a missing mapping. For a company with configured AP/Input VAT/EWT-Payable/Cash accounts, `fn_resolve_account` returns exactly those accounts (equivalence — the basis of GL equality). Every Purchasing writer populates `posting_origin`; the direct-insert Vendor Credit writer additionally tags `line_role`.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect the three Purchasing writers | Each resolves via `fn_resolve_posting_account`; none reads `company_accounting_config`. |
| 2 | Inspect out-of-scope code | An out-of-scope reconciliation report still reads config (non-vacuous scope guard). |
| 3 | Resolve a configured key via the adapter | Returns the configured account. |
| 4 | Resolve a missing key via the adapter | Re-raises the friendly "not configured" message. |
| 5 | Compare resolver output to config | `fn_resolve_account` equals the configured AP/Input VAT/EWT-Payable/Cash accounts. |
| 6 | Inspect posting metadata | Every Purchasing writer populates `posting_origin`; Vendor Credit tags `line_role`. |

## POSTING-ENGINE-P2C-001 - Inventory resolver certification (COA Engine Phase B, group 3)

Status: Pending first green run (added 2026-07-25) in `supabase/tests/085_posting_engine_p2c_inventory_resolver_test.sql`, 5 assertions, run in every regression and canonical lane. **P2C is an evidence-based certification, not a forced migration, and adds no migration file.** Investigation established that the four Inventory posting writers (`fn_post_goods_issue_source_locked_impl`, `fn_post_physical_count_source_locked_impl`, `fn_post_stock_adjustment_source_locked_impl`, `fn_post_stock_transfer_source_locked_impl`) already satisfy the frozen Phase P2 invariant: they read **zero** `company_accounting_config`. They resolve posting accounts from explicit, per-entity account ownership — `items.inventory_account_id`/`items.cogs_account_id` (goods issue), `items.inventory_account_id`/`warehouses.gl_variance_account_id` (physical count), `items.inventory_account_id`/line `gl_offset_account_id` (stock adjustment), and `warehouses.gl_inventory_account_id` (stock transfer), with line-level `gl_*_account_id` overrides. No inventory writer is changed. Item/warehouse-scoped inventory account resolution through `fn_resolve_account` is **outside the frozen P2 scope**: it would require new mapping keys (INVENTORY/COGS/VARIANCE/OFFSET) and, for warehouse-scoped accounts, a `warehouse_id` qualifier the frozen `account_mapping` contract does not have — a future COA enhancement project after the Posting Engine resolver migration completes. Inventory posting behavior is unchanged (no code touched); the full regression and canonical inventory postings remain green.

Scenario: the four Inventory writers exist and none (impl or wrapper) reads `company_accounting_config`; each resolves accounts from item/warehouse-scoped ownership; `ref_mapping_key` has no inventory/COGS/variance key (documenting the future-work boundary); and the config-read detector is non-vacuous (it fires on an out-of-scope reconciliation report `fn_ap_subledger_gl_reconciliation_asof`, which does read config).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Enumerate the Inventory writers | The four Inventory posting writers are present. |
| 2 | Inspect config reads across impls + wrappers | No Inventory posting writer reads `company_accounting_config` (P2 invariant already satisfied). |
| 3 | Inspect account sources | Every Inventory writer resolves accounts from item/warehouse-scoped account ownership. |
| 4 | Inspect the resolver key catalog | `ref_mapping_key` has no inventory/COGS/variance key — item/warehouse-scoped resolution is future COA work. |
| 5 | Verify the detector is non-vacuous | An out-of-scope reconciliation report still reads `company_accounting_config`, so the config-read assertion is meaningful. |

## POSTING-ENGINE-P2D-001 - Banking/Payments/Purchase-return resolver adoption (COA Engine Phase B, group 4)

Status: Pending first green run (added 2026-07-25) in `supabase/tests/086_posting_engine_p2d_banking_payments_resolver_test.sql`, 11 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260724000005_posting_engine_p2d_banking_payments_resolver.sql`. Certifies that the four remaining forward posting writers that read `company_accounting_config` — `fn_post_payment_voucher` (AP_TRADE, SUPPLIER_DOWNPAYMENTS, EWT_PAYABLE, CASH_DEFAULT), `fn_post_check_voucher` (EWT_PAYABLE), `fn_complete_purchase_return_source_locked_impl` (AP_TRADE), `fn_post_withholding_remittance` (EWT_PAYABLE, EWT_WITHHELD) — now resolve accounts exclusively through the certified COA resolver `fn_resolve_account` (via the `fn_resolve_posting_account` adapter) with no accounting behavior change. **Unlike P2A/P2B, P2D makes no metadata change: `posting_origin`/`line_role` are left exactly as they were, honoring the byte-for-byte-equivalent constraint.** Byte-for-byte GL equality of real postings is proven by the full regression + canonical lanes (Payment Voucher: 001/006/034/043/051 and canonical 055/057 which post 5 vouchers; Check Voucher: 022/023/036; Purchase Return: 031; Withholding Remittance: 036 — all with exact GL assertions, remaining green). Investigated and **certified without change** (already zero `company_accounting_config`): the Banking forward writers (bank adjustment / fund transfer / inter-branch transfer, sourcing `bank_accounts.gl_account_id`) and every reversal/void writer (which reverse the original posted journal and resolve no accounts). Out of scope (not posting writers): the `*_gl_reconciliation` reports, GL-impact previews, and `fn_save_withholding_remittance` (a save-time config-presence validator that writes no journal). This completes P2 resolver adoption for every forward posting family — zero forward posting writer reads `company_accounting_config`.

Scenario: the four migrated writers reference `fn_resolve_posting_account` and none reads `company_accounting_config`; the already-compliant Banking/reversal writers read zero config (certified unchanged); an out-of-scope reconciliation report still reads config (non-vacuous scope guard). The adapter returns the configured account for a resolvable key and re-raises the writer's friendly "not configured" message on a missing mapping. For a company with configured AP/Supplier-Downpayments/EWT-Payable/EWT-Withheld/Cash accounts, `fn_resolve_account` returns exactly those accounts (equivalence — the basis of GL equality).

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect the four migrated P2D writers | Each resolves via `fn_resolve_posting_account`; none reads `company_accounting_config`. |
| 2 | Inspect the Banking/reversal writers | Already read zero `company_accounting_config` (certified without modification). |
| 3 | Inspect out-of-scope code | An out-of-scope reconciliation report still reads config (non-vacuous scope guard). |
| 4 | Resolve a configured key via the adapter | Returns the configured account; re-raises the friendly "not configured" message on a missing mapping. |
| 5 | Compare resolver output to config | `fn_resolve_account` equals the configured AP/Supplier-Downpayments/EWT-Payable/EWT-Withheld/Cash accounts. |

## POSTING-ENGINE-P3A-001 - Dimension Push (Posting Engine Phase P3A)

Status: Executed Passing (2026-07-25) in `supabase/tests/087_posting_engine_p3a_dimension_push_test.sql`, 28 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260725000001_posting_engine_p3a_dimension_push.sql`; full pgTAP regression passed **87 files / 1,813 assertions** and the canonical lane passed **15 files / 307 assertions**. Implements objective O-A only of the frozen phase specification `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md` §3 (sub-phase P3a); P3B fiscal close, P3C manual-JE control, and P3D preview convergence are not implemented.

`fn_add_posting_line` is now a pure persistence helper: it accepts all six governed dimensions explicitly (`p_project_id`/`p_location_id`/`p_functional_entity_id` added, `DEFAULT NULL`), performs exactly one insert, and performs no source-document lookup, no `'VB'`/`'CP'` document-type dispatch, no follow-up `UPDATE journal_entry_lines`, and no dimension inference. The two writers that depended on the retired pull — `fn_post_vendor_bill` and `fn_post_cash_purchase_source_locked_impl` — now own dimension resolution and push the document header's six dimensions onto every line; their bodies are otherwise verbatim from the certified P2B migration. The helper's admission and accounting controls (journal `FOR UPDATE` lock, `is_company_member`, `fn_require_postable_account`, exactly-one-positive-amount) and its `authenticated`/`service_role` EXECUTE grants are preserved unchanged, so `permissions` and error messages are byte-for-byte identical. The Dimension Engine guard `trg_je_line_dimensions_guard` remains the only dimension validator and now sees pushed values on the same `INSERT`.

Deployment safety (spec Risk R3): PostgreSQL treats the 9-argument and 12-argument forms as distinct functions and rejects a 9-argument call against both at CALL time with `function ... is not unique`, so an additive overload is **not** deployment-safe. The migration drops the 9-argument function and creates the 12-argument one, re-applying the prior `REVOKE`/`GRANT` set verbatim; every surviving 9-argument call site still resolves.

Audit-event difference (the only permitted behavioral difference, spec §3.8 / Risk R2): a Vendor Bill / Cash Purchase line is written by one `INSERT` instead of `INSERT`-then-`UPDATE`. `journal_entry_lines` carries no audit trigger, so no `sys_audit_logs` or `transaction_events` row changes; the difference is one fewer statement and one fewer redundant firing of the line guards. No GL value changes.

Scenario: post a real Vendor Bill (expense / input VAT / AP / accrued EWT) and a real Cash Purchase (expense / input VAT / EWT withheld / cash) whose headers carry all six governed dimensions, then void the bill; assert the complete resulting GL and every line dimension against the pre-P3A output of the same fixture.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect `fn_add_posting_line` in `pg_proc` | Exactly one signature, twelve parameters, eight defaulted; no source lookup, no `reference_doc_type` dispatch, no follow-up UPDATE, exactly one INSERT, no dimension COALESCE inference. |
| 2 | Inspect the posting-line helper family | No helper reaches back into `vendor_bills`/`cash_purchases` for dimensions (zero pull dispatch). |
| 3 | Inspect EXECUTE privileges | `authenticated` and `service_role` retain EXECUTE; `anon`/PUBLIC remain denied. |
| 4 | Inspect the two migrated writers | Both push all six `v_rec` dimensions on every posting line. |
| 5 | Post a dimension-bearing Vendor Bill | Four lines: DR expense 10,000, DR input VAT 1,200, CR AP 11,000, CR EWT payable 200 — identical line numbers, accounts, descriptions, and amounts to the pre-P3A run. |
| 6 | Read the Vendor Bill lines' dimensions | All four lines carry the branch, department, cost center, project, location, and functional entity from the bill header. |
| 7 | Read the Vendor Bill metadata | `line_role` remains NULL on all four lines; `posting_origin` remains `system`. |
| 8 | Post a dimension-bearing Cash Purchase | Four lines: DR expense 10,000, DR input VAT 1,200, CR EWT payable 200, CR cash 11,000 — identical to the pre-P3A run; all four carry all six dimensions. |
| 9 | Void the posted Vendor Bill | Reversal journal (`REV`) posts; its four lines preserve all six dimensions. |
| 10 | Call the helper with nine arguments on a `'VB'`-typed journal whose bill carries all six dimensions | The line is created with the pushed branch and NULL department/cost-center/project/location/functional-entity — the helper infers nothing from the source document. |
| 11 | Push a cross-company department through the helper | The Dimension Engine guard rejects it (`does not belong to company`), proving the guard is the validator and is not vacuous. |

## POSTING-ENGINE-P3C-001 - Manual Journal Control (Posting Engine Phase P3C)

Status: Executed Passing (2026-07-25) in `supabase/tests/088_posting_engine_p3c_manual_je_control_test.sql`, 30 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260725000002_posting_engine_p3c_manual_je_control.sql`; full pgTAP regression passed **88 files / 1,843 assertions** and the canonical lane passed **16 files / 337 assertions**. Implements objective O-D only of the frozen phase specification `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md` §6, enforcing the frozen COA Posting Control Contract (`PXL_COA_ENGINE_SPEC.md` §5); P3D preview convergence is not implemented.

`fn_assert_manual_postable` was delivered by COA Phase A and had **zero runtime callers** since (certification observation O3). This phase wires it into `fn_post_manual_je` as a single `PERFORM` inside the existing per-line validation loop, placed **after** the existing account checks (belongs to company / `is_postable` / `is_active`) so every pre-P3C rejection keeps its exact message. The journal date is passed as the as-of date, so effective dating is evaluated at the accounting date rather than wall-clock time. The function body is otherwise verbatim from its certified definition (migration `20260723000003`); the signature, permissions, audit behavior, numbering (`MJE-YYYYMM-NNNN`), and posting pipeline are untouched.

**Exactly one live rejection is added.** `fn_assert_manual_postable` = `fn_assert_postable_leaf` (→ `fn_is_account_postable`: `is_postable`, `lifecycle_status='active'`, leaf-ness, effective window) plus the control-account test. Against the certified database the first four predicates are provably inert — the existing loop rejects non-postable/inactive accounts first, `fn_coa_change_policy_guard` keeps `is_active` in sync with `lifecycle_status`, zero postable accounts have children, and zero accounts carry `effective_from`/`effective_to`. The control-account test is therefore the only predicate that can fire.

**Canonical safety, verified before implementation:** whole database — 0 accounts flagged `is_control_account`, 0 journal lines of any document type on a control account, 0 postable non-leaf accounts, 0 effective-dated accounts. Replaying the validator over every existing `journal_entry_line`, at both the journal date and `CURRENT_DATE`, rejects 0 rows. No existing data is invalidated, so spec Open Question Q2 (grandfathering) needs no remediation.

**Non-vacuity, proven by construction and by reversion.** The canonical dataset has no control accounts, so a canonical-only assertion would prove nothing. The test builds an **attribution pair**: two accounts identical in every attribute the validator inspects — type, normal balance, postable, active, lifecycle, leaf, effective dating — differing **only** in `is_control_account`. The flag is set at creation because `fn_coa_change_policy_guard` makes `is_control_account` immutable once an account has posted history. The unflagged twin accepts the posting; the flagged one is rejected on either the debit or the credit side. Independently, restoring the pre-P3C function body and replaying the same posting **accepts** it and creates a journal on the control account — the hole the guard closes is real.

Scenario: prove the wiring and its order structurally; prove the guard rejects a genuine control account and that the flag is the sole cause; prove the other validator predicates are inert; prove a representative spread of valid manual journals (regular / adjusting / opening / auto-reverse / dimensioned / multi-line / null-branch) is unchanged; prove every pre-existing rejection message is preserved.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect `fn_post_manual_je` in `pg_proc` | Calls `fn_assert_manual_postable`; one signature; the call sits after the `is inactive` check; the journal date is passed as as-of. |
| 2 | Compare the attribution pair | Two accounts identical except `is_control_account`. |
| 3 | Post a manual JE against the non-control twin | Succeeds. |
| 4 | Post the same manual JE against the control account, debit side then credit side | Both rejected: "control account … may not be posted by a manual journal … must originate from the owning subledger". |
| 5 | Inspect the database after rejection | No journal header and no journal line persisted — fail-closed. |
| 6 | Inspect callers of the validator | Only `fn_post_manual_je` — subledger/posting writers are unaffected. |
| 7 | Inspect leaf, effective-dating, and lifecycle predicates | All inert: 0 postable non-leaf accounts, 0 effective-dated accounts, 0 lifecycle/`is_active` divergences. |
| 8 | Replay the validator over every existing journal line | Rejects nothing. |
| 9 | Post regular / dimensioned / adjusting / auto-reverse / null-branch manual JEs | Numbering, `entry_class`, `reference_doc_type`, `auto_reverse`, totals, line order, accounts, descriptions, amounts, and all six dimensions identical to the pre-P3C output. |
| 10 | Trigger each pre-existing failure mode | Too-few-lines, unbalanced, foreign account, negative amount, both-sides, closing class, and no-open-period messages all unchanged. |
| 11 | Post to an account inactive from creation | Still raises the original "is inactive" message, not the validator's — validation order preserved. |
| 12 | Call `fn_assert_manual_postable` directly | Rejects the control account; accepts an ordinary postable leaf. |

## POSTING-ENGINE-P3D-001 - GL Preview Resolver Convergence (Posting Engine Phase P3D)

Status: Executed Passing (2026-07-25) in `supabase/tests/089_posting_engine_p3d_preview_resolver_test.sql`, 38 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260725000003_posting_engine_p3d_preview_resolver.sql`; full pgTAP regression passed **89 files / 1,881 assertions** and the canonical lane passed **17 files / 375 assertions**. Implements objective O-C only of the frozen phase specification `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md` §5 — the resolver-convergence subset that closes COA certification observation O2. **This is NOT the full Preview ≡ Actual certification:** shared physical Posting Plan builder identity, `source_fingerprint` equivalence, and the whole-census preview/posted grid remain P8.

**Census (live `pg_proc`).** Five GL-facing preview functions exist. Only **one** projects posting accounts of its own — `fn_preview_sales_invoice_gl_impact_aud053_core`. Every other supported document type previews through `fn_preview_gl_impact_core`, which executes the **real posting writer** inside a plpgsql subtransaction and rolls it back through a marker exception (`__PXL_GL_PREVIEW_ROLLBACK__`); those paths therefore already resolve accounts exactly as actual posting does and are certified unchanged. `fn_gl_impact_payload` renders an already-posted journal and is also certified unchanged: all ten of its `company_accounting_config` references are the join key plus nine `WHEN jel.account_id = cfg.x` **provenance comparisons** that derive the descriptive `account_source` label from an already-resolved line — it resolves no posting account.

**Migration.** `fn_preview_sales_invoice_gl_impact_aud053_core` now obtains its two projected posting accounts from the certified adapter instead of `company_accounting_config`: AR via `fn_resolve_posting_account(company, 'AR_TRADE', v_rec.date, …)` and Output VAT via `fn_resolve_posting_account(company, 'VAT_OUTPUT', v_rec.date, …)` — the same two keys, friendly messages, and as-of expression `fn_post_sales_invoice` uses (P2A). No new mapping key, qualifier, schema change, or payload change. Signature, return type, SECURITY DEFINER, pinned `search_path`, and grants are unchanged (`CREATE OR REPLACE`, no overload).

**As-of date.** The **invoice date** (`v_rec.date`) is used, matching actual posting exactly. The preview's own display date may differ when a caller passes `p_posting_date` or a posted journal carries another `je_date`; resolving on the display date would let preview drift from actual. Both are identical today (zero effective-dated `account_mapping` rows).

**Failure behavior.** Resolution is deliberately non-fatal in preview: an unresolvable mapping yields NULL so the established external contract still renders a **structured blocker** (`account_code = 'Missing AR Account'`, `account_id` NULL) instead of a raw exception. This is a strengthening — a mapping that is missing, ambiguous, inactive, non-postable, wrong-typed, out of its effective window, or in another company now all surface as the same structured blocker, where previously only a NULL config column did. Actual posting still raises, unchanged.

**Non-vacuity, proven by controlled reversion.** Restoring the pre-P3D body and re-pointing the `AR_TRADE` mapping away from the config column shows the old preview displaying the **config** account while the resolver — and therefore actual posting — used the mapping account. That is precisely the O2 drift, and P3D closes it (assertion 38).

**Before/after equality.** On the *same* seeded database, pre-P3D and post-P3D bodies produce **byte-for-byte identical** preview output across every supported path (SI projected, SI posted, explicit posting date, generic dispatcher SI route, and the OR/VB/CP/PV/CM/DM rollback-preview routes). A cross-reseed comparison showed revenue lines in different positions; this was traced to the pre-existing ordering key `ORDER BY revenue_account_id::TEXT`, which is sensitive to canonical UUIDs regenerated on each reseed, and is unaffected by P3D.

Scenario: inventory the five preview functions; prove the migrated core resolves through the adapter on the invoice date with no direct config-derived account; prove the unchanged paths' ownership models; execute a real preview and compare its accounts to the resolver and to the posted journal; prove payload shape, ordering, and amounts; prove preview has no side effects; prove the fail-closed blocker; prove drift detection.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inventory GL-preview functions in `pg_proc` | Exactly the five censused functions; none overloaded. |
| 2 | Inspect the migrated SI preview core | Calls `fn_resolve_posting_account`; zero `v_cfg.x AS account_id`; uses `AR_TRADE` + `VAT_OUTPUT`; as-of = `v_rec.date` on both keys. |
| 3 | Compare to actual posting | `fn_post_sales_invoice` resolves `AR_TRADE` on the same `v_rec.date` (as-of parity). |
| 4 | Inspect preview adapter discipline | No preview function calls `fn_resolve_account` directly. |
| 5 | Inspect `fn_gl_impact_payload` | Every config reference is the join key or a provenance comparison; it resolves no account and renders posted lines. |
| 6 | Inspect `fn_preview_gl_impact_core` | Non-SI preview executes the real writer inside a rolled-back subtransaction. |
| 7 | Inspect routing | Wrapper → migrated core; dispatcher → wrapper; no caller reaches an obsolete implementation. |
| 8 | Inspect signature and grants | Returns `jsonb`; SECURITY DEFINER with pinned `search_path`; `authenticated` retains EXECUTE on the entry point. |
| 9 | Preview a real saved invoice | AR and Output VAT line accounts equal the certified resolver results. |
| 10 | Read preview lines and totals | Line order, account codes, `account_source` labels, debits, credits, and totals unchanged; payload balanced. |
| 11 | Read payload key sets | Top-level (17 keys) and line (27 keys) sets unchanged. |
| 12 | Compare state before/after preview | No journal, line, tax-ledger, inventory, event, or number-series change; document status untouched. |
| 13 | Post the previewed invoice | Every previewed account, amount, and line position equals the posted journal. |
| 14 | Preview an invoice whose company has no `AR_TRADE` mapping | The resolver raises at the seam, but preview returns a structured payload with `account_code = 'Missing AR Account'` and a null `account_id`. |
| 15 | Re-point the `AR_TRADE` mapping away from the config column | Preview follows the resolver, not the config column — O2 drift closed. |

## POSTING-ENGINE-P4-001 - Tax Boundary Certification (Posting Engine Phase P4)

Status: Executed Passing (2026-07-26) in `supabase/tests/090_posting_engine_p4_tax_boundary_test.sql`, 49 assertions, run in every regression and canonical lane. **No migration ships with this phase** — P4 was re-scoped by the architecture board from "introduce the TaxComponent shape" to a formal certification of the ownership boundary that already exists, so production behavior is unchanged by construction. Full regression passed **90 files / 1,930 assertions** on a clean `supabase db reset --local --no-seed` replay; the canonical lane passed **18 files / 424 assertions**. Governing contract: `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md` §2.2, §5.3, and the new §5.3.1 (Amendment A2).

**Historical boundary at execution; superseded by PAD-001.** When P4 ran, no formal Tax Engine or `TaxComponent` contract existed, and the test correctly proved that contemporary boundary. PAD-001 subsequently delivered `fn_calculate_tax`, migrated all eleven tax-calculation/validation consumers and separated Cash Sale calculation from posting. Test `090` remains a Posting Engine non-computation guard; it must not be read as a current claim that the Tax Engine is absent. Tax Engine certification remains separate and outstanding.

**Census (live `pg_proc`, authoritative over prose).** **20** tax-aware posting writers reach the General Ledger and reference VAT/EWT/CWT/withholding/tax. This corrects the investigation's count of 19: `fn_cancel_check_voucher` reverses the Check Voucher journal through `fn_bt_reverse_je` rather than `fn_reverse_posted_journal_entry` and was missed by a predicate keyed only on the latter. It computes no tax and reverses tax detail through the same certified function as the other four correction writers, so the correction enlarges the census without changing any conclusion. The remaining **30** GL writers are provably not tax-aware after P5.1 removed one unused legacy line helper, so the partition remains complete.

**Non-computation proof.** Of the 20, **zero** read `company_accounting_config` for an account; **19** contain no tax arithmetic and read no VAT rate source; **six** read `atc_codes`, and in five of them the rate is copied straight into `tax_detail_entries.tax_rate` as provenance — it never feeds a multiplication, division, or policy comparison. The precise certified claim is therefore *the posting layer records the rate that applied; it does not select one.* Schema-wide, tax-rate arithmetic exists in exactly **11** functions — 7 document-save VAT calculators, 2 EWT-profile appliers, 2 stored-amount validators — of which exactly one writes the GL: `fn_save_cash_sale`, whose calculation belongs to its document-save half. The detectors are proven non-vacuous: the same predicates fire on `fn_save_cash_sale` and stay silent on the pure-consumption writers.

**Ownership matrix at execution.** Tax policy and calculation then lived in the document-save layer; PAD-001 has since moved that ownership to the governed Tax Engine. Tax account resolution remains with the certified COA Resolver, tax-line construction remains with the Posting Engine, and tax-detail persistence/reversal remains with the Tax Ledger. This historical P4 evidence certifies none of the later Tax Engine implementation.

**Reversal provenance, proven non-vacuously.** The certified reversal copies the original ATC version, rate, taxable base, tax/VAT code, income nature, and linkage, negating only base and amount. Non-vacuity is engineered rather than asserted: the fixture closes the original `WC140` ATC version and opens a governed successor at a **different** rate (5.00 vs 2.00) effective on the reversal date, so a reversal that recomputed at the current rate would produce 250.00. The certified reversal reproduces the original 100.00 at the original 2.00 rate, and the original ledger row is left untouched.

**Rounding.** All seven calculators share one idiom — `ROUND(base * rate / 100, 2)` per line. Behaviourally, the same 100.05 base at 12% rounds to 12.01 in every reachable document calculator (Sales Invoice, Vendor Bill, Cash Purchase, Credit Memo, Vendor Credit), with no calculator disagreeing. **Documented limitation:** VAT-inclusive treatment is implemented in exactly one of the seven (Sales Invoice), and the test pins that fact so the Tax Engine program inherits it explicitly.

Scenario at P4 execution: census the tax-aware posting writers and prove the partition complete; prove structurally that the posting layer selects no rate and performs no tax arithmetic; prove COA ownership of tax accounts and Tax Ledger ownership of tax detail; prove the then-current absence of a Tax Engine; execute every supported tax-bearing canonical transaction and compare the stored tax fact, posted GL tax line and tax-ledger entry; prove zero-variance reconciliation, reversal provenance, rounding consistency and fail-closed invalid-tax behavior. Later Tax Engine evidence is recorded under tests `117`–`129`.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Census tax-aware GL writers in `pg_proc` | Exactly the 20 censused writers; the other 30 GL writers are provably not tax-aware; none overloaded. |
| 2 | Scan the census for VAT rate sources and rate arithmetic | Only `fn_save_cash_sale` reads `vat_codes`/`tax_codes` or uses a rate in arithmetic. |
| 3 | Census tax arithmetic schema-wide | Exactly 11 functions; exactly one of them writes the GL. |
| 4 | Census the document-save VAT calculators | Exactly the seven registered as Tax Engine debt. |
| 5 | Scan the census for configuration reads and tax keys | Zero `company_accounting_config` reads; exactly the four certified COA tax keys; every one resolved through `fn_resolve_posting_account`. |
| 6 | Inspect the five ATC-rate readers | The rate feeds no arithmetic and no policy comparison — provenance only. |
| 7 | Census tax-ledger writers and reversers | Eight writers; one reversal implementation consumed by five correction writers. |
| 8 | Search for a Tax Engine or tax-component builder | None exists. |
| 9 | Post SI, VB (source EWT), CP, PV (payment EWT), OR (CWT), CM, VC | For each: stored tax amount == posted GL tax line == tax-ledger amount, with ATC, rate, base, and income-nature provenance where applicable. |
| 10 | Save-and-post a Cash Sale with CWT | The posting half consumes the VAT its save half persisted (360.00 in document, GL, and ledger); caller-supplied CWT is recorded identically in GL and ledger. |
| 11 | Run `fn_vat_gl_reconciliation` and `fn_wht_gl_reconciliation` | Every tax kind reconciles at variance exactly 0.00 — not tolerance-satisfied. |
| 12 | Close the original ATC version and open a successor at a different rate | The rate in force on the reversal date is 5.00, not the document's 2.00. |
| 13 | Cancel the posted Payment Voucher | The counter-row carries the original 2.00 rate, original ATC version, base, and income nature; it does not adopt 5.00 and does not recompute to 250.00; the original row is untouched; exactly one counter-row exists. |
| 14 | Void a posted Sales Invoice | The counter-row copies the VAT code and exactly negates the original; the reversal journal debits Output VAT exactly what the original credited. |
| 15 | Save the same 100.05 base at 12% through five calculators | 12.01 everywhere; no calculator disagrees. |
| 16 | Post a VAT-inclusive and a VAT-exclusive invoice | 11,200 gross backs out to 10,000 + 1,200; 10,000 net grosses up to 11,200; both post unchanged. Inclusive treatment exists in exactly one calculator. |
| 17 | Tamper stored header VAT, then post | Rejected with the certified "header VAT does not match line VAT" message; no partial journal remains. |
| 18 | Supply withholding off the governed ATC rate | Rejected — fail-closed. |
| 19 | Search for a `TaxComponent` type or a posting writer consuming one | Neither exists; the contract remains deferred to the Tax Engine. |

## POSTING-ENGINE-P5A-001 - Surface Closure (Posting Engine Phase P5.0)

Status: Executed Passing (2026-07-26) in `supabase/tests/091_posting_engine_p5a_surface_closure_test.sql`, 45 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260726000001_posting_engine_p5a_surface_closure.sql`; full pgTAP regression passed **91 files / 1,975 assertions** and the canonical lane passed **19 files / 469 assertions**. Implements only the three items approved after the P5 architecture review. Governing contract: `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md` §4.6 (the Kernel Totality Guard this phase deliberately does **not** build) and §7 phase P5.

**What this did NOT do at P5.0.** P5.0 was not the Kernel Totality Guard; it closed the **external** (PostgREST / `authenticated` / `anon`) surface only. The later approved P5.1 migrations now coexist with that closure. Assertions 42-43 were advanced accordingly: the observe-only guard remains wired and every forward header INSERT is drained without reopening the P5.0 client surface.

**Why the ledger was not the exposure.** `journal_entries` and `journal_entry_lines` already carry RLS with a SELECT policy and **zero write policies**, so `authenticated` is denied by absence of policy despite holding table grants. The exposures were adjacent: an internal helper left callable, PUBLIC EXECUTE grants, and six **derived** accounting tables that any company member could author directly.

**The demonstrated bypass.** Before this migration, the identical statements by the identical genuine member succeeded: `UPDATE stock_balances SET wac_unit_cost = wac_unit_cost * 10` affected 1 row, and a forged `INSERT INTO inventory_transactions` inserted 1 row. `fn_post_sales_invoice` reads `stock_balances.wac_unit_cost` to compute COGS, so a member could pre-set valuation and have the certified engine post a COGS figure derived from tampered state — accounting impact created outside the Posting Engine, with no journal and no accounting audit. After the migration the same statements yield `UPDATE 0` and an RLS violation. **This controlled reversion is the non-vacuity proof**, executed against the seeded canonical dataset.

**Ownership premise, verified not assumed.** All 28 functions that write the six closed tables are SECURITY DEFINER, so every legitimate path executes as the table owner and is unaffected by RLS. The frontend reads all six and writes none. No pgTAP test writes them while impersonating `authenticated`.

**Two candidates deliberately excluded — a material correction to the investigation.** `bank_recon_items` and `book_tax_reconciliation` were named as P5.0 candidates on the premise that their writers were all SECURITY DEFINER. That premise is **false**: `BankReconciliationPage.tsx` writes `bank_recon_items` directly (`.delete()`/`.insert()`) and `BookToTaxReconciliationPage.tsx` writes `book_tax_reconciliation` directly (`.insert()`/`.update()`). Closing them would have broken working features, which the accounting contract forbids. They remain member-writable, and assertion 44 pins that state so it reads as a decision rather than an oversight.

**Two pre-existing assertions were re-pointed, not weakened.** Test 087 asserted that P3A *preserved* the `authenticated` EXECUTE grant on `fn_add_posting_line`; P5.0 is the approved decision that removes it, so the assertion is **inverted** — it now pins the closed state, and a regression that re-grants the helper still fails. Test 080 Section C simulated the Vendor Bill writer by calling the helper from the member role; that call now runs with the owner's privilege, which is how the real SECURITY DEFINER caller invokes it. Every dimension assertion in 080 is unchanged.

**Accounting equality, measured.** The canonical dataset was seeded and fingerprinted with the migration removed, then again with it applied: GL (`je_number`/status/date/source/totals/`posting_origin`/line number/account code/debit/credit/description/`line_role`/branch), tax detail, inventory movements, stock balances, and number series all hash **identically** (GL `75ddb2e4…`, TAX `50469c66…`, INV `d5e87b88…`, STOCK `31af15fa…`, SERIES `39ee27a6…`; 48 journals / 138 lines / 24 tax rows / 26 movements).

Scenario: pin the closed helper and the client-entry surface; prove no GL writer is reachable by `anon` while every legitimate caller keeps exactly the privilege it had; prove the six derived tables deny every `authenticated` write while the SECURITY DEFINER writer still posts through them unchanged; prove the phase boundary; pin the deliberate exclusions.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Probe `fn_add_posting_line` privileges | Not executable by `authenticated` or `anon`; owner retains EXECUTE. |
| 2 | Probe every internal journal/tax persistence helper | None is callable by `authenticated`. |
| 3 | Scan GL writers for `anon` and PUBLIC grants | Zero of each. |
| 4 | Compare the ten client entry points before/after | `authenticated` and `service_role` retain EXECUTE; `anon` does not. |
| 5 | Enumerate the authenticated-reachable GL-writing surface | Exactly the ten client entry points. |
| 6 | Inspect the three journal-linking trigger functions | Unreachable by `anon`/`authenticated`; all seven triggers still exist. |
| 7 | Inspect policies on the six closed tables | RLS on; three deny-all write policies each; every write expression is `false`; the SELECT policy is preserved. |
| 8 | Inspect the ledger's own policies | `journal_entries`/`journal_entry_lines` unchanged (two SELECT policies); `tax_detail_entries` unchanged (four). |
| 9 | Inspect every writer of a closed table | All SECURITY DEFINER. |
| 10 | Confirm the probing identity | A genuine member that can read the closed table — denials are not vacuous. |
| 11 | Attempt INSERT on four closed tables as the member | Each raises `42501`. |
| 12 | Attempt the UPDATE/DELETE battery as the member | Runs without error and touches nothing — denial is by row filtering, not privilege. |
| 13 | Re-read all closed state | Quantity, valuation, row count, movements, cost layers, and schedule ledgers unchanged; the ledger untouched. |
| 14 | Post a Sales Invoice with an inventory item through the writer | Posts; five lines AR/Revenue/Output VAT/COGS/Inventory with the certified amounts; header totals and status unchanged. |
| 15 | Re-read inventory after posting | Stock decremented by 10, valuation maintained, exactly one movement recorded, tax detail unchanged, all five lines carry the branch. |
| 16 | Inspect later-phase compatibility | The P5.1 observe-only guard coexists with the P5.0 external closure. |
| 17 | Count direct-insert forward writers | Zero outside the sanctioned header kernel. |
| 18 | Inspect the two excluded tables and `fiscal_periods` | Still member-writable / MDP-03 permission-gated, by recorded decision. |

## POSTING-ENGINE-P51-001 - Kernel Totality Guard, Stage 1 (Posting Engine Phase P5.1)

Status: Executed Passing (2026-07-26) in `supabase/tests/092_posting_engine_p51_kernel_guard_test.sql`, 40 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260726000002_posting_engine_p51_kernel_guard_observe.sql`; full pgTAP regression passed **92 files / 2,015 assertions** and the canonical lane passed **20 files / 509 assertions**. Governing contract: `PXL_POSTING_ENGINE_SPEC.md` §4.6 / §4.6.2 and §7 phase P5.1.

**The guard is NOT armed.** It records; it rejects nothing. Later approved stages migrated the remaining writers and met the arming gate without changing assertion 7's observe-only boundary. Assertion 40 now pins zero forward header INSERTs outside the kernel.

**Origin is proven by call stack, not by a flag — a deliberate departure from the frozen wording.** §4.6 suggests "a transaction-scoped posting-context flag set only by the kernel". A settable flag is precisely the shape that produced Critical `PXL-AUD-070` (the `pxl.allow_demo_reset` GUC that `authenticated` could set). This implementation instead reads `GET DIAGNOSTICS ... PG_CONTEXT`: a write is kernel-origin if and only if a sanctioned kernel is genuinely on the plpgsql call stack, which a caller cannot fabricate. Assertion 17 proves the point by setting both `pxl.posting_kernel` and `pxl.allow_demo_reset` and showing the direct write is still classified as a violation. The guard reads no session setting at all (assertion 6), and enforcement is a **compile-time constant**, not a runtime knob — there is nothing to flip at session scope.

**Honest scope of the control:** this is a *discipline* control, not an authorization control. Authorization is owned by RLS, closed in P5.0, where the ledger already carries zero write policies for `authenticated`. The guard's threat model is in-database code — a future function, migration, or developer shortcut writing the ledger outside the kernel.

**Material finding — the 7-argument kernel could not absorb the writers.** Verified against the live catalog before any code was written: 23 of the 24 direct-insert writers resolve their own fiscal period and raise their **own** user-visible "No open fiscal period …" message (23 distinct wordings, three of them asserted by existing tests); every one writes computed header totals while the kernel writes 0/0 and relies on `fn_finalize_journal_entry`, which none of them calls; four set `posting_origin` and three set `entry_class`/`auto_reverse`, none of which the 7-argument kernel can express. Routing them through the kernel as-is would therefore have changed 23 user-visible behaviours and every migrated header's totals. The kernel is instead **extended additively** so a writer hands it what it already writes and keeps its own validation and messages verbatim. Per the P3A finding an additive overload is not deployment-safe, so the function was dropped and re-created with defaulted parameters; all seven existing 7-argument callers keep resolving and behave identically (assertion 39).

**Material finding — the runtime census is larger than the static one.** Observe-only mode surfaced violations the `pg_proc` census could not: `fn_post_sales_invoice`, `fn_post_vendor_bill`, `fn_post_receipt`, and `fn_post_cash_purchase_source_locked_impl` are all "already kernel-routed" for the header INSERT, yet each mutates the header afterwards with a direct `UPDATE journal_entries` (28 events in the canonical replay). Direct `journal_entry_lines` INSERTs are the other large surface. The remaining migration is therefore header INSERTs **plus** header UPDATEs **plus** line INSERTs, not header INSERTs alone. The census is a *runtime* census over exercised paths and complements, rather than replaces, the static §4.7 census — the canonical dataset exercises 9 writers, not all 24.

**Module 1 migrated: the memo posters (CM / DM / VC).** Chosen first because the three are uniform, self-contained, and already set every header column the extended kernel now carries. The transformation was performed **mechanically** — each original body was read from `pg_proc` and only the header `INSERT` block was replaced by the kernel call, with a line-level diff confirming 11-12 lines removed and 8 added in each, all inside that block. An earlier hand-reconstruction of two of these functions was discarded after the diff showed it had drifted in five ways, including silently dropping a `tax_detail_entries` write.

**Accounting equality, measured.** The canonical dataset was fingerprinted before P5.0 and again after P5.1 Stage 1 — GL (`je_number`/status/date/source/totals/`posting_origin`/line number/account code/debit/credit/description/`line_role`/branch), tax detail, inventory movements, stock balances, and number series all hash **identically** (GL `75ddb2e4…`, TAX `50469c66…`, INV `d5e87b88…`, STOCK `31af15fa…`, SERIES `39ee27a6…`; 48 journals / 138 lines / 24 tax rows / 26 movements).

Scenario: prove the guard exists, is structural, has no forgeable marker, and is not armed; prove it discriminates kernel from non-kernel origin using an attribution pair that differs only in origin; prove forgery fails; prove the evidence table is engine-owned; prove `posting_origin` capability; prove Module 1 posts identically through the kernel; prove the kernel extension is deployment-safe; pin the phase boundary.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Inspect the guard triggers | Wired to both ledger tables, BEFORE INSERT/UPDATE/DELETE. |
| 2 | Inspect the guard function | SECURITY DEFINER with pinned `search_path`; not callable by `authenticated`/`anon`; derives origin from `PG_CONTEXT`; reads no session setting; enforcement is a `false` compile-time constant. |
| 3 | Inspect the kernel whitelist | Exactly the two sanctioned kernels plus their persistence helpers. |
| 4 | Inspect the evidence table | RLS on; three deny-all write policies; membership-scoped read. |
| 5 | Write the ledger from a non-kernel SECURITY DEFINER function | Succeeds (observe-only) **and** is recorded, naming `probe_direct` as the writer. |
| 6 | Write the same header through the kernel | Succeeds and is **not** recorded. |
| 7 | Set `pxl.posting_kernel` and `pxl.allow_demo_reset`, then write directly | Still recorded — the call stack cannot be forged. |
| 8 | Inspect `posting_origin` | Governed `system`/`manual` domain; kernel default NULL preserves legacy callers; an explicitly supplied value persists. |
| 9 | Inspect the three Module 1 writers | None inserts a header directly; all three call the kernel; each keeps its own period message. |
| 10 | Post a Credit Memo, Debit Memo, and Vendor Credit | Header status/totals/`posting_origin`/`entry_class`/`auto_reverse`/source, line order/accounts/amounts/`line_role`, tax detail, and document status are all the certified values. |
| 11 | Check audit rows for the three migrated journals | Audit coverage unchanged. |
| 12 | Check the header violation census for Module 1 | Zero — the migration is behaviourally proven, not just structurally. |
| 13 | Count kernel signatures | Exactly one — no ambiguous overload. |
| 14 | Count remaining direct-insert writers | Zero outside the sanctioned header kernel. |

## POSTING-ENGINE-P51-002 - Stage 2, Module 2 (memo posters: line persistence)

Status: Executed Passing (2026-07-26) in `supabase/tests/093_posting_engine_p51_stage2_test.sql`, 28 assertions, run in every regression and canonical lane after a clean `supabase db reset --local --no-seed` replay including migration `20260726000003_posting_engine_p51_stage2_module2.sql`; full pgTAP regression passed **93 files / 2,043 assertions** and the canonical lane passed **21 files / 537 assertions**. Governing contract: `PXL_POSTING_ENGINE_SPEC.md` §4.6.2.

**The Kernel Totality Guard remains OBSERVE-ONLY.** Stage 2 does not arm it; `c_enforce` is untouched and assertion 27 pins that.

**What this completes.** Stage 1 moved the CM / DM / VC header INSERTs into the sanctioned kernel; Module 2 moves their nine direct `journal_entry_lines` INSERTs into the sanctioned persistence helper. The three memo posters now touch **neither** ledger table directly, and the guard classifies them as kernel-origin on both.

**Helper choice was forced, and the alternative would have been a validation change.** The memo lines carry `line_role` (`base`/`tax`/`control`), which `fn_add_posting_line` cannot express. More importantly, `fn_add_posting_line` imposes `fn_require_postable_account` **and** a debit/credit-exclusivity check that the raw INSERTs being replaced never performed — routing through it would have introduced two new rejection paths, which the phase contract forbids. `fn_add_posting_line_push` — the push-based helper P1/P3A built for exactly the §4.2 additive line columns, unreferenced until now — performs the same single INSERT, so the persisted row is identical. Assertions 6-7 pin both halves of that reasoning, including that the rejected alternative genuinely does add validation.

**Transformation method: mechanical, not hand-written.** Each body was read from `pg_proc`, each `INSERT INTO journal_entry_lines (…) VALUES (…)` block parsed by paren matching, `company_id` and the two trailing `auth.uid()` audit columns dropped (the helper supplies all three), and the remaining seven arguments emitted in helper order. A line-level diff confirmed the only changes were those nine call sites. This method was adopted after Stage 1, where a hand-reconstruction of two writers had silently dropped a `tax_detail_entries` write.

**Two corrections to assumptions, both verified against the live schema rather than assumed.** First, journal lines are **not** dimension-free after the migration: the certified Dimension Engine guard `fn_je_line_dimensions_guard` defaults a NULL line `branch_id` from the journal header on INSERT, and it fires identically for the helper and for the raw INSERT it replaced — so lines inherit the header branch, before and after. Second, `journal_entry_lines` carries **no** `fn_audit_trigger`; line-level audit does not exist (the Audit Engine covers 79 tables, and journal lines are protected by the posted-document immutability guards instead), so this migration could not change line audit coverage either way. Assertions 11 and 24 record both facts so neither reads as a regression.

**Violation-table delta.** Canonical replay went from **9 writers / 79 events** to **7 writers / 73 events**; `fn_post_credit_memo_vat_lump_impl` and `fn_post_vendor_credit_vat_lump_impl` are fully drained (`fn_post_debit_memo_vat_lump_impl` is not exercised by the canonical dataset and is proven drained by test 093 instead).

**Accounting equality, measured.** Canonical fingerprints are **identical** to the pre-P5.0 baseline across GL, tax detail, inventory movements, stock balances, and number series (GL `75ddb2e4…`, TAX `50469c66…`, INV `d5e87b88…`, STOCK `31af15fa…`, SERIES `39ee27a6…`).

Scenario: prove the module is fully migrated structurally; prove the helper choice preserves validation exactly; post a Credit Memo, Debit Memo, and Vendor Credit and compare header, line grid, ordering, `line_role`, descriptions, dimensions, tax detail, numbering, and document status against the certified values; prove header audit coverage; prove the violation delta is zero for the module; pin the guard's observe-only state and the phase boundary.

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Scan the three memo writers for direct ledger writes | None — neither `journal_entries` nor `journal_entry_lines`. |
| 2 | Scan them for kernel and helper use | All three use the kernel for the header and the helper for lines; the CM poster makes three helper calls. |
| 3 | Inspect the sanctioned set and helper grants | The push helper is kernel-origin and callable by no client role. |
| 4 | Compare the two line helpers | The push helper adds no account validation; `fn_add_posting_line` does — which is why it was not used. |
| 5 | Post a Credit Memo | Header status/totals/`posting_origin`/`entry_class`/`auto_reverse`/source/`je_number` unchanged; three lines in order with certified accounts, amounts, `line_role`, and descriptions; lines inherit the header branch and carry no analytical dimensions; tax detail and document status unchanged. |
| 6 | Post a Debit Memo | Control line first, then base, then tax; header and tax detail unchanged. |
| 7 | Post a Vendor Credit | Control/base/tax lines and header unchanged; document status `open`. |
| 8 | Compare number series | Three documents consumed exactly three numbers. |
| 9 | Check header audit rows | Each migrated journal header audited exactly once. |
| 10 | Check line audit triggers | None exist — line audit coverage is unchanged by construction. |
| 11 | Check the violation census for the module | Zero on both tables; posting three memo documents added no violation at all. |
| 12 | Inspect the guard and the writer count | Guard still OBSERVE-ONLY; later approved stages leave zero direct-insert forward writers. |

## POSTING-ENGINE-P51-003 through P51-010 - Writer migration and ready-to-arm closure

Status: Executed Passing (2026-07-26) in:

- `supabase/tests/094_posting_engine_p51_stage3_batch_a_test.sql` — 15 assertions; Sales Invoice, Vendor Bill, Receipt, Cash Purchase header UPDATE paths.
- `supabase/tests/095_posting_engine_p51_stage4_manual_journal_test.sql` — 22 assertions; isolated Manual Journal certification.
- `supabase/tests/096_posting_engine_p51_stage5_inventory_test.sql` — 18 assertions; Goods Issue, Physical Count, Stock Adjustment, Stock Transfer GL persistence only.
- `supabase/tests/097_posting_engine_p51_stage6_treasury_test.sql` — 12 assertions; Bank Adjustment, Fund Transfer, Inter-Branch Transfer, Petty Cash Voucher approval, Petty Cash Replenishment, Check Voucher.
- `supabase/tests/098_posting_engine_p51_stage7_assets_schedules_test.sql` — 16 assertions; depreciation, amortization, revenue recognition, asset registration/disposal/impairment, and source-link updates.
- `supabase/tests/099_posting_engine_p51_stage8_system_generated_test.sql` — 14 assertions; recurring journals and fiscal close.
- `supabase/tests/100_posting_engine_p51_stage9_commerce_test.sql` — 16 assertions; Purchase Return and Cash Sale.
- `supabase/tests/101_posting_engine_p51_ready_to_arm_test.sql` — 20 assertions; zero-writer census, exact classifier, sanctioned mutation surface, observe-only state, and readiness.

The owning migrations are `20260726000004`–`20260726000011`. The continuation adds **133 assertions**; tests `091`–`101` pass 246 assertions together. The full clean regression passes **101 files / 2,176 assertions** and deterministic canonical replay passes **29 files / 670 assertions**.

**Accounting contract equality.** Journal headers, totals, status, source, origin, entry class, auto-reverse metadata, journal lines, line order, line role, descriptions, dimensions, audit rows, tax detail, inventory movements/layers/balances, number series, document lifecycle, reversal behavior, and preview output remain byte-for-byte equal to the certified outputs. Canonical fingerprints remain the pre-P5.0 values (GL `75ddb2e4…`, TAX `50469c66…`, INV `d5e87b88…`, STOCK `31af15fa…`, SERIES `39ee27a6…`).

**Manual Journal isolation.** The P3C validator remains after all legacy account checks and before totals; period locking and its message remain before numbering; the seven established rejection messages, `MJE-YYYYMM` numbering, NULL `posting_origin`, `entry_class`, auto-reverse, dimension carriage, and line order are unchanged.

**Inventory stop-condition result.** No Inventory Engine redesign was necessary. Only journal header/line persistence moved; WAC, layers, balances, movements, warehouse/item account ownership, and the `INV_COUNT` zero-line carve-out remain intact.

**Totality result.** All 24 authoritative forward writers plus the four separately observed header-UPDATE paths contain zero direct mutation of `journal_entries` or `journal_entry_lines`. Only `fn_create_posted_journal_entry`, `fn_reverse_posted_journal_entry`, `fn_finalize_journal_entry`, `fn_add_posting_line`, `fn_add_posting_line_push`, and `fn_add_sales_invoice_posting_line` retain ledger DML. The unused legacy core helper is removed. Classifier matching is exact-name anchored; lookalikes fail and the six-member sanctioned set does not grow.

**Violation and origin result.** Canonical replay produces **0 writers / 0 violation events**, including zero non-maintenance events. Of 48 canonical journals, 30 carry approved explicit `posting_origin='system'`; 18 remain NULL (Inventory, Manual, Payment Voucher, and reversal paths). No historical or ambiguous origin was inferred or backfilled.

**Kernel classification.** `c_enforce` remains the compile-time constant `false`. The guard records and rejects nothing. The readiness gate is met: zero legitimate violations and zero forward direct mutations. The Kernel Totality Guard is **READY TO ARM but is not armed**; arming and enforcement-mode certification require a separate governed approval.

The preceding paragraph records the completed P5.1 phase boundary. P5.2 below supersedes its observe-only runtime state without changing any P5.1 accounting result.

## POSTING-ENGINE-P52-001 - Kernel Totality Guard arming and enforcement certification

Status: Executed Passing (2026-07-26) in `supabase/tests/102_posting_engine_p52_enforcement_security_test.sql`, 78 assertions, after a clean replay including `20260726000012_posting_engine_p52_arm_totality_guard.sql`. The complete read-only catalog output is reproducible with `supabase/verification/p52_kernel_security_census.sql`.

**Material findings.**

1. `authenticated` retained legacy table-level INSERT/UPDATE/DELETE grants despite having no ledger write policies. INSERT reached the guard, but UPDATE/DELETE could be converted by RLS to successful zero-row statements rather than the required hard rejection. P5.2 revokes all three DML privileges from `PUBLIC`, `anon`, and `authenticated`; all six direct client operation/table combinations now fail with `42501`.
2. An ordinary trigger can be skipped by a privileged replay helper setting `session_replication_role = replica`. Both totality triggers are therefore `ENABLE ALWAYS`; the replay attack reaches and fails the guard.
3. Rejected-statement evidence cannot durably remain in `sys_posting_guard_violations`: PostgreSQL rolls back the evidence INSERT with the statement that raises. The table remains a zero-census readiness/observe artifact; P5.2 rejection is proven by SQLSTATE and the absence of persisted mutation.

**Enforcement configuration.** The guard's compile-time constant is `true`. Maintenance classification no longer bypasses it. The classifier remains exact-name anchored and unchanged at six members. The guard function is not executable by client roles; ledger DML is not granted to client roles. Both totality triggers are always enabled. No whitelist, heuristic, runtime flag, historical backfill, or engine redesign was introduced.

**Unauthorized-mutation matrix.** The test attempts INSERT, UPDATE, and DELETE on both `journal_entries` and `journal_entry_lines` through eight paths: authenticated, anon, non-kernel SECURITY DEFINER helper, SQL-script helper, authenticated RPC, migration helper with the historical maintenance GUC enabled, replay helper with that GUC plus replica trigger mode, and direct owner SQL. This is 48 attacks:

- Authenticated and anon: 12/12 rejected with insufficient privilege (`42501`).
- All in-database, RPC, maintenance, replay, and owner paths: 36/36 rejected by the Kernel Totality Guard (`23514`).
- Persisted unauthorized mutations: 0.
- Guard violations after the matrix: 0, because every guard-raised statement is atomic and rolls back its attempted mutation and evidence row.

**Authorized posting matrix.** The full regression and canonical suites execute representative Sales, Vendor Bill, Receipt, Payment, Credit Memo, Debit Memo, Vendor Credit, Cash Purchase, Manual Journal, Inventory, Fixed Asset, Recurring, Fiscal Close, and Reversal paths. Each reaches the ledger only through one of the six sanctioned persistence functions and succeeds under enforcement. Recurring execution is also exercised through the certified rollback-preview path, which invokes the real writer and proves the guard permits it without committing preview state.

**Complete security census.**

- Application functions: 409.
- Application SECURITY DEFINER functions: 349.
- Direct or transitive ledger-mutating functions: 80; all 80 are SECURITY DEFINER and reach a sanctioned kernel.
- Direct ledger mutators: exactly 6 — `fn_create_posted_journal_entry`, `fn_reverse_posted_journal_entry`, `fn_finalize_journal_entry`, `fn_add_posting_line`, `fn_add_posting_line_push`, `fn_add_sales_invoice_posting_line`.
- Explicit EXECUTE ACL rows: 950, covering all 409 application functions; the census enumerates every grantee/signature row.
- Direct service-role access among the six kernels: 3 — create, add-line, and add-line-push. Service role has no classifier exception and must genuinely execute the kernel.
- Ledger persistence triggers: 21; the two totality triggers are `ENABLE ALWAYS`.
- Ledger RLS policies: 2, both SELECT-only (`je_read`, `jel_read`).
- Client-writable ledger tables: 0.
- Remaining directly client-writable accounting-adjacent workflow tables: 2 (`bank_recon_items`, `book_tax_reconciliation`), retained by the recorded P5.0 decision; neither can mutate the ledger.

The census script emits the complete 80-function call graph, every EXECUTE grant, every SECURITY DEFINER function, every ledger trigger, all 488 public RLS policies, the writable-accounting-table census, and the final enforcement invariants. The test creates its attack helpers only after catalog census assertions, so test-only functions cannot pollute the production census.

**Accounting and replay equality.** Fresh canonical replay produces 48 journals / 138 lines / 24 tax rows / 26 inventory movements; total debit and total credit are both `2,411,134.80`; `posting_origin` remains 30 explicit `system` / 18 valid NULL; guard violations are zero. GL, journal header, journal lines, line ordering/role, numbering, dimensions, audit, tax, inventory, document status, preview, and reversal assertions all pass. The certified pre-P5.0 fingerprints remain identical (GL `75ddb2e4…`, TAX `50469c66…`, INV `d5e87b88…`, STOCK `31af15fa…`, SERIES `39ee27a6…`).

**Executed lanes.**

- Focused enforcement: 1 file / 78 assertions.
- P5.1/P5.2 compatibility: 11 files / 279 assertions.
- Full clean regression: 102 files / 2,254 assertions.
- Fresh canonical migration, reset, base/enrichment/volume replay: pass.
- Canonical suite: 30 files / 748 assertions.
- Canonical violation count: 0.

The Kernel Totality Guard is **FULLY ENFORCED**. This completes P5.2 only; P6 has not begun.

## POSTING-ENGINE-P6-INVESTIGATION-001 - Mandatory stop at Inventory reconciliation

Status: **Blocked — certification not executed** (2026-07-26). This is read-only investigation evidence, not a passing test and not a migration. P5.2 remains unchanged and authoritative.

The P6 investigation independently recomputed canonical inventory quantity/value from `inventory_transactions`, compared it to `stock_balances`, compared remaining layers to both, and compared the source result to journal lines on every configured item `inventory_account_id`. No tolerance was used.

| Company | Opening movement value | RR increase | Other increase | Decrease | Movement/stock ending | Inventory GL | Exact variance | Layer ending | Layer variance |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ABC Trading Corporation | 71,200.00 | 2,400.00 | 720.00 | 3,140.00 | 71,180.00 | 68,780.00 | 2,400.00 | 73,600.00 | 2,420.00 |
| Bayani Partners and Company | 52,500.00 | 21,000.00 | 2,100.00 | 14,700.00 | 60,900.00 | 39,900.00 | 21,000.00 | 73,500.00 | 12,600.00 |
| Golden Retail Store | 44,300.00 | 6,000.00 | 2,400.00 | 6,330.00 | 46,370.00 | 39,740.00 | 6,630.00 | 50,300.00 | 3,930.00 |

The quantity recomputation itself is exact between movements and stock: 243 / 29 / 176 units respectively. Cost-layer remaining quantities are 252 / 35 / 190, producing variances of 9 / 6 / 14 units.

**Root cause evidence.**

- The three Receiving Reports increase stock by exactly 2,400.00 / 21,000.00 / 6,000.00 and carry no `journal_entry_id`.
- The corresponding Vendor Bills post those base amounts to account `5010 Purchases / Inventory Clearing`, not the configured item Inventory account `1200`.
- ABC's Vendor Credit later credits clearing by 200.00 but does not reduce stock, leaving stock 200.00 above Inventory plus clearing.
- Golden begins with 44,300.00 in inventory movements/stock but only 43,670.00 in the opening Inventory journal, leaving an additional 630.00 difference.
- Layer quantities/values do not reflect the same issues/adjustments as stock.

This cannot be certified by changing only a report. Combining Inventory and purchase clearing heuristically still leaves real differences; adjustments would force equality; changing receipt/vendor-credit/layer behavior would redesign or modify the Inventory/Posting contract; changing canonical inventory would violate the certified inventory equality baseline. Each is an explicit stop condition.

**Stop result.** No P6 migration, report, validation, or test was introduced. AR and AP were observed to reconcile exactly in the current canonical state, but they were not promoted to P6 certification because the phase stopped before the full six-domain proof. Fixed Asset, Bank, and Tax P6 certification were not executed. No P7 work began.

## INVENTORY-IA5-001 - Dormant event, identity, precision, projection, and security foundation

Status: Executed Passing (2026-07-26) in
`supabase/tests/103_inventory_accounting_ia5_foundation_test.sql`, 99 assertions.
The genuine two-session extension is
`supabase/verification/ia5_concurrent_idempotency.sql`, 7 assertions. The complete
read-only writer/grant catalog is
`supabase/verification/ia5_inventory_writer_security_census.sql`.

The scenario proves:

- exact company/source-document/source-line/transition/partial-occurrence identity;
- stable per-scope economic ordering independent of UUID order;
- immutable event, source-link, amount, allocation, occurrence, policy, and scope
  facts, including under replica trigger mode;
- exact `NUMERIC(38,6)` quantities, `NUMERIC(38,8)` authoritative amounts,
  `NUMERIC(38,12)` UOM/rate evidence, scale/overflow rejection, derived-unit-rate
  separation, and structural residual-allocation metadata;
- sequential and concurrent duplicate idempotency, legitimate partial/source-line/
  cross-company isolation, rollback retry, and changed-request rejection;
- complete rollback after failures before accepted occurrence completion;
- zero external EXECUTE grants on all IA-5 functions and no client/service DML on
  any IA-5 table;
- internalization of `fn_receive_inventory(jsonb)` while its two governed owner
  callers remain wired;
- unchanged current Inventory writers, movements, layers, balances, canonical
  fixtures, and accounting behavior;
- exactly six journal mutators, two always-enabled P5.2 guards, and zero violations.

## INVENTORY-IA5-ECC-WP1-001 - Order-policy and version foundation (dormant)

Status: Executed Passing (2026-07-26) in
`supabase/tests/104_inventory_accounting_ia5_ecc_wp1_order_policy_foundation_test.sql`,
22 assertions, after a clean `supabase db reset --local --no-seed` replay including
migration `20260726000016_inventory_accounting_ia5_ecc_wp1_order_policy_foundation.sql`.
Certifies IA-5 ECC Hardening Work Package 1 (the six dormant version tables), covering
evidence families T-01 (deterministic tuple — structural at this stage) and T-27
(dormancy). Governed by the frozen `IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md`
§24/§17(M1) and authorised by `ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md`.

The scenario proves:

- exactly the six ECC order-policy/version tables are installed
  (`inventory_event_order_policies`, `inventory_event_effect_ranks`,
  `inventory_source_type_ranks`, `inventory_transition_ranks`,
  `inventory_canonical_form_versions`, `inventory_correction_graph_versions`), each
  carrying `company_id` and a CHECK-pinned `activation_state` dormancy column;
- dormancy and security: no client/service role holds INSERT/UPDATE/DELETE on any
  table, RLS is enabled with a membership-scoped SELECT policy on all six, and the
  new guard function has no role EXECUTE grant;
- the certification-only rank set materialises — E3 effect ranks are the frozen
  sparse convention `opening=10/increase=20/value_only=30/decrease=40/allowance=50`,
  the E4 source-type rank and E7 transition rank are seeded for
  `IA5_CERTIFICATION`/`ACCEPTED`, and the version vector V (order policy + canonical
  form + correction graph) resolves company-consistently with a sha256 digest identity;
- ENABLE-ALWAYS immutability rejects UPDATE and DELETE on the version rows;
- the guard rejects a rank whose company differs from its order policy (P-02), an
  overlapping order-policy version, duplicate ranks, and a non-dormant activation_state;
- WP-1 adds nothing to `inventory_events` and writes no journal entry (Posting/Kernel
  boundary unchanged).

Fresh canonical replay remains 48 journal headers / 138 journal lines / 24 tax rows /
26 Inventory movements with debit = credit = `2,411,134.80`. All five certified
fingerprints remain unchanged. The eleven company/event/projection IA-5 tables remain
empty under canonical workflows; IA-5 is additive and dormant.

The post-IA-5 live P5.2 census is 417 application functions / 354
`SECURITY DEFINER`; the eight added IA-5 signatures have zero client/service
EXECUTE. The original P5.2 boundary census of 409/349 remains historical evidence,
while test `102` now pins the current complete catalog.

## INVENTORY-IA5-ECC-WP2-001 - Registry authority evidence contract

Status: **Implemented — independent Evidence Gate passed; WP-2 CERTIFIED
2026-07-30.** Migration
`20260729000017` implements M2. Test `105` carries 48 assertions for the
registry and rolled-back certification fixture; test `106` carries 21
assertions for fixture cleanup and isolated structural rollback.

Implementation assets:

- `supabase/tests/105_inventory_accounting_ia5_ecc_wp2_registry_authority_test.sql`;
- `supabase/tests/106_inventory_accounting_ia5_ecc_wp2_rollback_test.sql`; and
- `supabase/migrations/20260729000017_inventory_accounting_ia5_ecc_wp2_registry_authority.sql`.

The controlling implementation design §23 owns the family numbers:

- **T-04 Source order (E4/E5):** WP-2 persists the exact E5 registry selector;
  its rolled-back certification fixture resolves one E4 rank for
  `IA5_CERTIFICATION`. Runtime document comparison belongs to later work.
- **T-06 Transition order (E7):** the rolled-back fixture resolves exactly one
  `ACCEPTED` transition rank and rejects missing, duplicate, or unknown
  transition authority. Runtime transition ordering belongs to later work.
- **T-07 Effect order (E3):** the exact `event_effect_map` and
  `same_time_class` resolve through the rolled-back effect-rank fixture and
  prove `increase = 20 < decrease = 40`. Runtime event ordering belongs to
  later work.
- **T-27 Dormancy:** persistent state proves zero events, no
  production-enabled source, no runtime consumer or new write grant, and no
  Posting or Kernel change.

“Registry completeness” is the combined WP-2 completion evidence and is not a
test-family name.

The M2 migration owns persistent assertions only: exact preconditions,
six columns and constraints, exact registry values, registry-local consistency,
unchanged row/event counts, unchanged RLS/grants/immutable-trigger state, no
runtime activation, and no persistent WP-1 policy/rank rows. The WP-2
test owns E3/E4/E7 cross-object resolution: it creates minimum
certification-only policy/rank data inside its transaction, reads but never
updates the persistent registry row, performs the structural/fixture portions
of T-04/T-06/T-07/T-27, and ends with `ROLLBACK`. Post-test evidence must prove
that no fixture user, company, policy, rank, event, journal, or other temporary
certification row survives. Structural rollback evidence runs separately in an
isolated test transaction against the M2-applied state, drops the six WP-2
columns in reverse dependency order, explicitly reasserts that the registry
contains exactly one row before the destructive drops, proves the pre-M2 shape,
and then rolls back the test transaction so that the M2-applied state is
restored.

Evidence Gate validation: focused tests `105`/`106` pass 69/69; fresh migration
replay passes; full regression passes 106 files / 2,444 assertions; canonical
accounting passes 30 files / 748 assertions. `inventory_events` remains zero,
the registry contains one exact certification row, no fixture row survives,
and canonical accounting totals/fingerprints do not change. The independent
Evidence Gate recommended WP-2 certification and the separate Certification
Mission granted it on 2026-07-30, having re-executed every lane, probed the
applied catalog, and mutation-verified that test `106`'s single-row precondition
fails closed on an extra registry row. Certification covers the WP-2 work
package only; the IA-5 permanent-foundation claim remains suspended under C-01.

## INVENTORY-IA5-ECC-WP3-001 - Stream partition and allocator evidence contract

Status: **Implemented — independent Evidence Gate passed; WP-3 CERTIFIED
2026-07-31.** Migration
`20260730000018` implements M3. Test `107` carries 46 assertions for the
two-table structure and the rolled-back certification fixture; test `108`
carries 22 assertions for fixture cleanup and isolated structural rollback.

Implementation assets:

- `supabase/tests/107_inventory_accounting_ia5_ecc_wp3_valuation_streams_test.sql`;
- `supabase/tests/108_inventory_accounting_ia5_ecc_wp3_rollback_test.sql`; and
- `supabase/migrations/20260730000018_inventory_accounting_ia5_ecc_wp3_valuation_streams.sql`.

The controlling implementation design §23.2 owns the family allocation:

- **T-22 Multi-company isolation (P-02):** both tables carry `company_id` with
  RLS and one member-gated `SELECT` policy each; the rolled-back fixture proves
  two companies each hold a stream carrying the same `scope_code` for their own
  item, that a stream naming another company's item is rejected, that a
  duplicate `(company_id, item_id, scope_code)` is rejected `23505`, and that an
  allocator row whose company differs from its stream's is rejected. Runtime
  cross-company edge and order rejection belongs to later work.
- **T-26 Migration/backfill:** fresh `--no-seed` replay through M3 succeeds with
  `inventory_events` = 0 asserted before mutation, both tables created empty, no
  backfill, and every key, constraint, control, and trigger present.

"Stream partition completeness" is the combined WP-3 completion evidence and is
not a test-family name. No WP-3 test claims T-01, T-02, T-03, T-05, T-15, T-16,
T-19, T-21, or any part of C-01.

The M3 migration owns persistent assertions only: six fail-closed preconditions,
the exact two-table shape, the ten governed keys and constraints, the five
governed triggers, RLS/policy/grant state, both tables empty, no runtime
consumer, and no change to the legacy scope allocator. The WP-3 test owns the
certification fixture: it builds two companies, two items, two dormant policy
bundles, and two shared-`scope_code` scopes inside its transaction and removes
them by final `ROLLBACK`. Structural rollback evidence runs separately in an
isolated test transaction against the M3-applied state, reasserts exact total
row counts, drops both tables in foreign-key order plus the WP-3 guard function,
proves the pre-M3 state, and then rolls back so the M3-applied state is restored.

The deliberate mutability asymmetry is asserted directly: the stream rejects
`UPDATE` and `DELETE` (`23514`) and carries the dormancy `CHECK`, while the
allocator carries neither an immutability trigger nor an `activation_state`
column, advances forward-only, freezes its identity columns, and rejects
`DELETE`.

Validation: fresh migration replay passes; focused tests `107`/`108` pass 68/68;
full regression passes 108 files / 2,512 assertions; canonical accounting passes
30 files / 748 assertions with debit = credit = `2,411,134.80` and variance
`0.00`. `inventory_events` remains zero and both WP-3 tables remain empty even
under the full canonical seed. WP-3 is **not** evidence-gated and **not**
certified; those are separate missions.

## INVENTORY-IA5-ECC-WP4-001 - Persisted ECC order-key evidence contract

Status: **WP-4 CERTIFIED 2026-07-31.** Its Brutal Audit failed only on
WP4-BA-001/WP4-BA-002, the bounded Brutal Fix closed both, the Brutal Audit
Re-run passed, and the separate Certification Mission granted work-package
certification. At the original Brutal Audit decision WP-4 was not brutally
fixed, not audit-re-run, and not certified.
Migration `20260731000019` implements authorised M4. Test `109` carries 71
assertions for the exact order-key structure and rolled-back fixture; test `110`
carries 30 assertions for fixture cleanup and isolated structural rollback.

Implementation assets:

- `supabase/tests/109_inventory_accounting_ia5_ecc_wp4_order_keys_test.sql`;
- `supabase/tests/110_inventory_accounting_ia5_ecc_wp4_rollback_test.sql`; and
- `supabase/migrations/20260731000019_inventory_accounting_ia5_ecc_wp4_order_keys.sql`.

The controlling implementation design §23 and the detailed WP-4 specification
§7 allocate only the structural/fixture portions of **T-03 Duplicate identity**
and **T-24 Immutability**. Test `109` proves both uniqueness boundaries, all 30
non-state columns immutable with `23514`, `DELETE` rejected with `23514`, the
one permitted `current` → `superseded` transition, the rejected reverse
transition, and all three company-isolation guard rules. It also proves the
exact 31-column, 24-key/constraint, four-explicit-index, two-trigger, RLS,
policy, grant, dormancy, and no-`inventory_events`-trigger boundaries. Test
`110` proves fixture residue is zero and exercises the authorised table-then-
function rollback inside a transaction whose final `ROLLBACK` restores M4.

Validation: fresh replay passes; focused tests `109`/`110` pass 101/101; full
regression passes 110 files / 2,613 assertions; canonical accounting passes 30
files / 748 assertions with debit = credit = `2,411,134.80` and variance `0.00`.
`inventory_events`, both WP-3 stream tables, and `inventory_event_order_keys`
remain empty under the full canonical seed. No resolver, writer, comparator,
runtime consumer, activation path, or trigger on `inventory_events` exists.
These were implementation results only at the implementation frontier. The independent
Brutal Audit verified the complete executable contract but failed on only
WP4-BA-001 (current authority-chain contradiction) and WP4-BA-002 (stale
generated schema summary). The bounded Brutal Fix closed both without changing
SQL, migration logic, tests, runtime behaviour, accounting, Posting, Kernel,
ADR, or ECC. The Brutal Audit Re-run then passed. Lifecycle Step 7 independently
re-executed fresh replay, focused `109`/`110` (2 files / 101 assertions), full
regression (110 / 2,613), canonical accounting (30 / 748), and direct catalog
controls before certifying WP-4. WP4-BA-003 and WP4-BA-004 remain non-blocking
and untouched. This certification applies only to WP-4.

---

## PXL-AUD-073 — Inventory-to-GL reconciliation guard

Status: **REMEDIATED 2026-08-02.** Confirming a Receiving Report increased
`stock_balances`, cost layers and `inventory_transactions` while producing no
journal entry, so inventory value drifted from its control account on every
goods receipt. Migration
`supabase/migrations/20260802000001_receiving_report_inventory_gl_posting.sql`
posts the receipt through the sealed doorway as
**DR inventory control / CR purchase clearing**, which the existing Vendor Bill
routine already clears on the invoice side. The migration also stops creating
cost layers for weighted-average items — every outflow path consumed layers only
for fifo / specific identification, so weighted-average layers accumulated and
could never deplete — and registers the governed `INVENTORY_CONTROL` and
`PURCHASE_CLEARING` account keys.

The same finding covers a seed defect: the canonical opening journal was valued
from a live `stock_balances` snapshot taken after later seed blocks had already
issued stock, so opening inventory in the ledger understated opening stock. The
opening journal is now valued from the opening receipts themselves.

Implementation assets:

- `supabase/tests/111_inventory_gl_reconciliation_guard_test.sql`; and
- `supabase/migrations/20260802000001_receiving_report_inventory_gl_posting.sql`.

Test `111` is a dataset-invariant guard in the style of `075`: it asserts over
whatever data is loaded rather than building an isolated fixture, so it holds
for the canonical demo seed and for a real company alike. It proves six
invariants — subledger equals control account to the centavo (R1), every
confirmed receipt carrying inventory value is posted (R2), every receipt journal
balances (R3), receipt journals touch only the two governed accounts (R4), no
weighted-average item retains an unconsumable cost layer (R5), and every company
holding stock has both governed account keys configured (R6).

This closes the first of the nine critical reconciliations. It certifies no
module and no engine.

---

## Fresh-data end-to-end purchase proof

Status: **PASSING 2026-08-02.** `supabase/tests/112_purchase_to_gl_fresh_data_e2e_test.sql`
provisions its own company, chart of accounts, fiscal calendar, number series,
warehouse, item, supplier and documents, then drives the real chain through the
production RPCs — `fn_save_purchase_order` → `fn_approve_purchase_order` →
`fn_save_receiving_report` → `fn_confirm_receiving_report` → `fn_save_vendor_bill`
→ `fn_approve_vendor_bill` → `fn_post_vendor_bill` — and proves the accounting
from first principles across 15 assertions.

**Why it exists separately from test `111`.** Test `111` asserts the
inventory-to-GL invariant over whatever dataset is loaded, which in practice is
the canonical demo seed. That seed was produced during early development by logic
that was not always correct: it shipped an opening journal ₱630 short of opening
stock because it valued opening inventory from a live `stock_balances` snapshot
taken after later seed blocks had already issued stock. Verifying a fix against
data that may encode the defect is circular.

**It immediately earned its place.** On first run it failed at
`fn_confirm_receiving_report` with `COA resolver: account … type liability does
not match expected expense for key PURCHASE_CLEARING`. The `PURCHASE_CLEARING`
key had been declared `expense` because that was inferred from the legacy demo
chart, where clearing is account `5010 Purchases / Inventory Clearing`. Goods
received not invoiced is conventionally a **liability**, which is what the
standard template ships as `2015` — so a **correctly configured company could not
receive stock at all**, while the legacy demo chart worked. The key now declares
no expected account type and accepts either shape. The canonical lane could never
have found this, because it only ever exercises the legacy chart.

Proven: the receipt posts exactly one journal (DR inventory control 25,000.00 /
CR purchase clearing 25,000.00); stock is 100 units at 25,000.00; the inventory
subledger equals the control account exactly; no cost layer is created for a
weighted-average item; posting the vendor bill returns purchase clearing to 0.00
with no stranded cost; accounts payable carries the full 28,000.00 VAT-inclusive
amount; the books balance at 0.00; and the net position is inventory on hand at
cost.

---

## Delivery Plan Phase 3 — opening-balance fresh-company proof

Status: **PASSING 2026-08-02.**
`supabase/tests/113_opening_balances_fresh_data_e2e_test.sql` provisions an
independent company and proves the PAD-002 cut-over contract across 31 assertions.
It drives the production save/post/reverse RPCs, rejects manually entered control
accounts and unbalanced or duplicate cut-overs, posts exactly one balanced opening
journal through the sealed doorway, and reconciles opening AR, AP, inventory and
bank balances to their live subledgers and General Ledger controls. The proof is
PHP-only and leaves `inventory_events` at zero.

## Delivery Plan Phase 3 — verified supplier payee proof

Status: **PASSING 2026-08-02.**
`supabase/tests/114_supplier_bank_payment_validation_test.sql` exercises the
supplier-bank and Payment Voucher contract on fresh tenant data across 15
assertions. A bank-transfer voucher fails closed without a verified bank account,
cannot select another supplier's account, snapshots verified instructions on the
posted voucher, and remains historically stable when the master is edited. The
voucher still posts one balanced journal through the Accounting Kernel and IA-5
remains dormant.

## Delivery Plan Phase 3 — minimum-administration contract

Status: **PASSING 2026-08-02.**
`supabase/tests/115_minimum_administration_contract_test.sql` proves PAD-003's
company-scoped membership, role and branch-scope RPCs across 14 assertions. It
includes duplicate branch-input normalization, owner-only owner changes,
administrator rejection when attempting to demote or remove an owner, last-owner
protection, and atomic branch-scope cleanup when a membership is removed.

## Delivery Plan Phase 3 — opening-subledger settlement proof

Status: **PASSING 2026-08-02.**
`supabase/tests/116_opening_subledger_settlement_e2e_test.sql` provisions a fresh
company, posts balanced opening AR/AP, and then uses the ordinary Receipt and
Payment Voucher save/post RPCs across 14 assertions. AR/AP ageing and General
Ledger control balances reduce by the settled amounts, explicit opening-item
relationships are preserved, over-application fails closed, and the opening batch
cannot be reversed after operational journals exist. `inventory_events` remains
zero.

Together tests `113`–`116` form the Phase 3 focused lane: 4 files / 74 assertions.

---

## Delivery Plan Phase 4 — Tax Engine calculator

Status: **PASSING 2026-08-03.**
`supabase/tests/117_tax_engine_calculator_test.sql` proves `fn_calculate_tax`,
the single Philippine tax calculator introduced by PAD-001, across 31 assertions
on a company it provisions itself. It covers VAT exclusive and inclusive pricing
(including the residual rule that makes net + VAT reconstitute a quoted price to
the centavo), zero-rated and exempt classification, an absent VAT code, the
rounding cases the seven former calculators had to agree on, expanded and final
withholding resolved by ATC, withholding computed on the VAT-exclusive base, the
governed effective-date window across a deprecate-and-succeed rate change, and
four fail-closed refusals of a malformed tax context.

Two structural companions carry the rest of the claim. Test `090` asserts that
exactly one function in the schema performs tax arithmetic, that no posting
writer performs any, and — through assertions that did **not** change across the
migration — that every migrated caller still produces identical stored tax,
posted GL tax lines, tax-ledger rows and GL reconciliations. Test `100`
assertion 6 pins Cash Sale to the engine while keeping its CWT validation.

Percentage tax is **not** asserted anywhere, because nothing calculates it and
no document reaches it. It is recorded in the Product Backlog, not claimed here.

## Delivery Plan Phase 4 — effective-dated VAT resolution

Status: **PASSING 2026-08-03.**
`supabase/tests/118_vat_effective_date_resolution_test.sql` closes the half of
Phase 4 the calculator left open. Withholding already resolved the ATC version in
force on the document date; VAT resolved `WHERE vc.id = <id>` and nothing else, so
a superseded, deprecated, deactivated or not-yet-effective VAT version still
computed tax, and a code that could not be resolved silently became `exempt at 0%`.

The file provisions its own VAT and non-VAT companies, performs a governed
deprecate-and-succeed VAT rate change (12% → 14%) on the real masters, and asserts
across 25 assertions that: the resolver `fn_resolve_vat_code` is the one place a
VAT code's validity is decided and both the engine and the trigger backstop ask it;
the superseded version still computes 12% on a document inside its window while the
successor computes 14% on a document inside its own; each version is refused
outside its window with a message naming the date; the engine returns the exact
tax-code version, rate and classification it resolved; deactivated and deprecated
codes are refused; a sale cannot use an input-VAT code and a purchase cannot use an
output-VAT code; a non-VAT company cannot use a VAT-bearing rate but may still use
a zero-rate code.

Section D asserts the rule is enforced by the **database**, not only by the save
RPCs: RLS lets a company member write document lines directly, so the line trigger
refuses a superseded code using the *invoice's* date rather than today, accepts the
same code on an invoice dated inside its window, and the header trigger re-validates
every line against the document date. Section E asserts the picker
`fn_vat_codes_asof` returns exactly what the resolver accepts, so the UI cannot
offer a code the database will refuse.

Assertion 25 deliberately pins an **open gap**: `companies.tax_registration` is a
single scalar with no history, so `fn_company_tax_registration_asof` accepts a date
it cannot yet honour. Every tax-profile read in VAT validation goes through that one
seam, which is what makes the future fix a one-function change; the fix itself is
recorded in the Product Backlog.

## Delivery Plan Phase 5 item 3 — Cash Sale posting

Status: **PASSING 2026-08-03.**
`supabase/tests/119_cash_sale_posting_test.sql` proves the outbound entry point Cash
Sale was missing. Before it, a cash sale of an inventory item credited revenue and
output VAT and left the stock on the books: no COGS, no inventory relief, no
`inventory_transactions` row — the one thing Sales Invoice had done since
PXL-AUD-053.

The file provisions its own retail company and posts one counter sale of **goods and
services together**, withheld under **two different ATCs**, across 26 assertions. It
asserts stock falls from 10 to 6 and its value by the 2,400 issued at weighted-average
cost; that exactly one `inventory_transactions` issue row exists and carries the
journal it was posted with; that the sold line points back at its own movement and
keeps the unit cost it was relieved at; that the sales journal debits COGS 2,400 and
credits inventory 2,400 and balances at 10,240 including the cost lines; and that
goods and service revenue reach their own accounts.

Withholding is asserted per line and all the way through: each line carries its own
ATC, base and the rate the Tax Engine resolved on the document date, and the tax
ledger carries **one `cwt_receivable` row per ATC** — which is what a 2307 and a
1601-EQ are assembled from, and what a single header ATC could never express. The
receipt settles the 100.00 total, declares `cwt_source = 'invoice_lines'`, debits CWT
receivable in full and pays cash net of it.

Section B asserts VAT-**inclusive** counter pricing, which Cash Sale could not do at
all before (it asked the engine without a price basis): a 1,120 quoted price backs out
to 1,000 net + 120 VAT, and still relieves its unit. Section C asserts the edges fail
closed — the document-level ATC convention is unchanged; mixing per-line and
per-document withholding is refused; selling stock the warehouse does not hold is
refused; an inventory line with no warehouse is refused rather than sold from nowhere;
and a line withholding code outside its effective window is refused, because the
engine still governs the ATC version by document date.

Three structural censuses moved as a consequence and were updated rather than
worked around: `100` assertion 8 (Cash Sale's posting-line sites went from six to
eight — the COGS debit and the inventory credit), and `103` assertion 25 (Cash Sale
legitimately joined the fifteen derived-table writers, using the shared
`fn_ensure_stock_balance` / `fn_consume_cost_layers` path, not a second costing
implementation). Test `090`'s ATC-reader census is unchanged: the withholding rate is
stamped on the line by the engine, so the posting layer never reads the ATC master.

Percentage tax is **not** asserted. A PT-registered company still computes none,
because the PT liability posting line and the 2551Q artifact do not exist.

## Delivery Plan Phase 5 item 3 — Sales outbound inventory flow

Status: **PASSING 2026-08-03.**
`supabase/tests/120_sales_outbound_inventory_flow_test.sql` closes the last two
ways stock could move without the ledger noticing, and proves them as one act
rather than as two functions.

A **Delivery Receipt** shipped goods and relieved nothing: stock stayed on the
books at full cost until somebody invoiced it, so a count taken between shipping
and billing disagreed with the ledger and no account explained the difference. A
**Customer Return** credited the customer and returned no stock, so gross margin
stayed overstated by the cost of every return ever processed.

The file provisions its own trading company and walks the whole outbound act
across 24 assertions: deliver five of twenty units, bill the delivery, then take
two back. It asserts that delivery relieves stock (20 → 15) and posts
**DR Goods Delivered Not Invoiced / CR Inventory** with **no COGS yet**, because
the sale has not happened; that posting the same delivery twice is a no-op rather
than a second relief; that billing the delivery moves **no stock at all** and
writes no inventory transaction of its own, recognising the 3,000 of COGS by
clearing the delivery account instead; that the clearing account **nets to zero**
once the delivery is billed; that a delivery line cannot be billed twice
(`uq_sil_delivery_source`); and that a return puts two units back at the 600 they
were issued at through the shared `fn_receive_inventory` path, reversing 1,200 of
COGS and 240 of output VAT.

The two closing assertions are the ones that matter for a pilot: inventory
reconciles to its control account across delivery, invoice and return, and net
COGS is 1,800 — the three units the customer actually kept.

Two prerequisites surfaced during implementation and were completed with it,
because the workflow is incorrect without either: `DR` had to be registered in
`ref_posting_source_types` (a delivery journal is impossible until it is, since
`journal_entries.reference_doc_type` is a foreign key into that registry), and
`fn_save_sales_invoice` had to accept `DR` as a line source with its own
validation that the source line is a *delivered* line of the same company and
customer.

Census consequences, updated rather than worked around: the COA template gained
account `1310` (43 accounts, tests `063`/`073`); the governed inventory movement
keys became three (`085`); the non-tax GL writer partition grew by one (`090`);
the Credit Memo poster now writes five helper lines (`093`); the ledger-capable
graph, function, SECURITY DEFINER and grant censuses each grew by one (`102`);
and the derived-table writer census is seventeen with the generic-receipt callers
at four (`103`).

Not claimed here: Quotation/Sales Order conversion (the Document Conversion
engine is not started). This file links the invoice to the delivery through the
governed `source_document_type` / `source_line_id` columns, which is what the
clearing consumption keys on. Financial statement presentation is now covered by
test `121` below.

## Delivery Plan Phase 5.7 — Financial statement presentation

Status: **PASSING 2026-08-03.**
`supabase/tests/121_financial_statement_presentation_test.sql` closes the gap
between a correct trial balance and a statement an accountant can sign.
`fs_structure` and `account_fs_map` had existed since the schema was laid down
and had **never held a single row**; the four Financial Statement screens
compensated by grouping postable accounts by `account_type` in the browser, with
the layout hardcoded in TSX.

The file provisions a company the normal way — standard 43-account template chart,
governed statement structure seeded with it, opening position posted through the
production cut-over RPC, then one real cash sale — and asserts across 25
assertions that the result is a statement rather than a grouped trial balance.

Section A asserts the configuration exists and is well-formed: all four
statements have a structure; **no account maps to more than one line of the same
statement**; every postable account reaches a position or income-statement line
*and* a cash-flow classification; the two cash accounts are marked
`is_cash_equivalent`; and no account is mapped to a subtotal or to current-year
earnings, because those are computed, not posted.

Section B runs the statements. Comprehensive income: revenue 4,000, cost of sales
shown as −2,400, and Gross Profit and Net Income **rolled up from the hierarchy**
rather than re-derived. Financial position: assets 8,080, liabilities 480,
current-year earnings 1,600 without any closing entry, **the statement balances**
(assets = liabilities + equity), and it **ties to the general ledger it came
from**. Cash flows: cash moved 4,480 and operating + investing + financing equals
that movement exactly — the statement's own proof — split −1,520 operating and
6,000 financing from the governed metadata. Changes in equity: opening plus
movement equals closing, and total equity agrees with the position.

Section C is the claim that matters for the future: **the layout is
configuration.** Re-mapping inventory to a different governed line moves 3,600 to
Non-current Assets and leaves total assets unchanged — presentation moved, the
ledger did not, and no code changed. That is what makes a local-GAAP or IFRS
re-presentation a data change rather than a release.

Not claimed: period close (revenue and expense balances are still not rolled into
retained earnings by any process — the governed `current_year_earnings` line is
what makes a mid-year position balance), comparative periods, note disclosures
and consolidation.

## Delivery Plan Phase 5 (Backlog 18d) — Period close and year-end roll-forward

Status: **PASSING 2026-08-03.**
`supabase/tests/122_period_close_year_end_rollforward_test.sql` runs the
accounting cycle to its end: transaction → posting → general ledger → trial
balance → statements → period close → year-end close → retained earnings → next
fiscal year.

**Why this file exists in the shape it does.** `fn_close_fiscal_year` had been in
the schema since PXL-AUD-013 and test `040` passed every assertion about it. It
could not have committed. The closing journal was posted with
`reference_doc_type = 'CLOSE'` and a NULL `reference_doc_id`, while the `CLOSE`
row of `ref_posting_source_types` pointed at `journal_entries`; the deferred
constraint trigger `trg_journal_entry_source_integrity` resolves every posted
entry's source at COMMIT and rejects a NULL source for a non-MANUAL type. pgTAP
rolls back, so a deferred constraint the suite never commits is a constraint the
suite never checks. The same transaction with `SET CONSTRAINTS ALL IMMEDIATE`
fails with "Posting source id is required for source type CLOSE". A year-end
close that passes its test and cannot commit is worse than one that is missing,
because the test says it is there.

The fix is not a patch: the fiscal year **is** the closing journal's source
document, so `CLOSE` now resolves against `fiscal_years` and the entry carries
`reference_doc_id = fiscal_year_id` with the source assertion enforced instead of
skipped. Assertion 23 asserts that resolution directly, so the gap cannot reopen
without a red test.

Section A pins the governance. `fiscal_periods.is_locked` and
`fiscal_years.status` are refused to a direct writer (assertions 1–2) — before
this, the "Close Year" button wrote `status = 'closed'` straight through
PostgREST and posted no journal at all, so a year could be declared closed with
revenue and expense still sitting in the profit-and-loss accounts. The close
register denies every direct write and enforces row-level security (3–4), and
readiness is returned as data, so the screen and the engine cannot disagree
(5–7).

Section B runs the monthly and quarterly close. A closed period locks and is
recorded with the readiness evidence that admitted it (8–10), refuses a second
close (11) and refuses further posting (12). Periods close in date order (13).
The quarterly close is the *same* period close applied to the quarter's
remaining periods (14–15) — PXL keeps a monthly fiscal calendar, so a quarter is
not a second closing concept. Reopening requires a reason (16), runs
last-in-first-out so a posting can never land behind a period that is still
closed (17), supersedes rather than erases the close it undoes (18–19), and the
register cannot be deleted (20).

Section C is the year-end close. The closing journal is balanced, classified
`closing` and sourced on the fiscal year (22); it satisfies the deferred
source-integrity constraint (23); revenue and expenses are zero afterwards
(24–25); retained earnings carries the year's net income of 75,000 (26); the
ledger still balances (27); the year is closed with every period locked (28);
and the **next fiscal year is open with its twelve periods and the same
retained-earnings destination** (29) — the roll-forward needs no operator step. A
second close is refused (30).

Section D is the claim that matters most: the close is repeatable, not
cumulative. Reopening requires a reason (31) and takes the net income back out of
retained earnings (32) by counter-posting the closing journal through the
Accounting Kernel. That counter-entry is itself classified `closing` (33), which
is precisely why closing the reopened year again lands 75,000 in retained
earnings rather than 150,000 (34): the aggregation that computes net income
ignores closing entries, so it never re-consumes its own reversal. The original
closing journal is never edited, voided or deleted — three immutable journals
stand in the ledger and net to one close.

**Committed evidence, separate from this file.** Because the defect above was
exactly a close that survives rollback and dies at COMMIT, the cycle was also run
end-to-end against a self-provisioned company with real COMMITs: monthly close,
quarterly close, year-end close (Dr Revenue 310,000 / Cr Expense 90,000 / Cr
Retained Earnings 220,000, trial balance out-of-balance 0.00), roll-forward into
FY2027, refusal of a second close, reopen, and re-close leaving retained earnings
at 220,000 rather than 440,000.

Not claimed: unposted source documents are not yet a readiness check (Backlog
18h), retained earnings is configured on the fiscal year rather than as governed
company configuration (18g), and comparative statements and note disclosures
remain outstanding (18e).

## Delivery Plan Phase 5 (Backlog 18e) — Comparative statements and basic notes

Status: **PASSING 2026-08-03.**
`supabase/tests/123_comparative_statements_and_notes_test.sql` completes the
reporting path: posted transactions → general ledger → trial balance →
current-period statements → comparative statements → basic notes.

**The regression this file exists to hold.** Period close (18d) shipped hours
earlier and, in doing so, silently broke two of the four statements for any
closed year. A closing journal debits the revenue accounts and credits the
expense accounts, and the report read every posted line regardless of
`entry_class`, so — measured on a fresh company before the fix —

* the Statement of Comprehensive Income of a **closed** year read as **all
  zeroes**: revenue of 50,000 became 0.00 the moment the year closed; and
* the Statement of Cash Flows **re-labelled the whole year**: 30,000 of
  operating cash flow moved to financing, because the closing entry's credit to
  Retained Earnings is an equity movement and equity is financing.

Nothing had ever closed a year until 18d, and comparatives are the first feature
that reads a closed year on purpose — the prior column would have been blank.
The rule now follows from what a closing entry is: **excluded** from the income
statement and the cash flow statement, **included** in the position and in
changes in equity, where retained earnings is only correct because of it.
Assertions 1–6 pin all four statements before and after a close.

Section B is period resolution. The comparative is not "last year" as a browser
understands it: `fn_resolve_comparative_period` reads the company's own fiscal
calendar, offsetting by a calendar year for consecutive twelve-month years and
falling back to matching fiscal period *numbers* for an irregular calendar.
A half-year compares against the same half (11). The honest answers come back as
data rather than exceptions — the earliest fiscal year has no comparative (12,
13) and a range crossing a fiscal-year boundary is refused with its own reason
(14) — while the report itself fails loudly when asked to compare nothing (15).

Section C runs all four comparative statements across two fiscal years, the
first of them closed. Revenue 150,000 against 100,000 is +50,000 and +50.00%
(16); net income 100,000 against 60,000 is +40,000 and +66.67% (17). The
comparison basis is a property of the statement, not of the screen: a
performance statement compares movements, a position compares balances (18, 19).
**The position balances in both columns** (21, 22), the cash flow statement ties
to the movement in cash in the comparative column too (24), and closing equity
agrees with the comparative position (26). A percentage against a nil base is
returned as NULL, because that is no percentage rather than a large one (27).

Section D is the claim that makes a comparative a comparative. The accounts
behind a line are fetched by the same signing rule as the line, so they sum to
the subtotal they were opened from (28, 29). Re-mapping cash to a different
governed line moves the current **and** the comparative column together (30) and
leaves total assets unchanged in both (31) — a comparative read on two different
structures compares nothing, so the prior period is deliberately presented as of
the *current* period end.

Section E is the notes. They are rows, not prose: every item names the
configuration or ledger fact behind it and carries whether that fact is actually
configured, so an unset policy reads as unset instead of silently reading as a
default (33).

**Real-data evidence, separate from this file.** On a self-provisioned company
with FY2026 closed and FY2027 open: revenue 1,100,000 against 800,000 (+37.50%),
net income 680,000 against 500,000 (+36.00%), assets 1,180,000 against 500,000
balancing against equity in both columns, the revenue line drilling to account
4010 at 1,100,000 / 800,000, and thirty-eight note items reporting `Not set` and
`is_configured = false` for revenue district office, BIR registration date, CAS
permit, depreciation and income tax, with trial-balance agreement 0.00 in both
periods.

Not claimed: this is not a complete PFRS or PFRS for SMEs disclosure set, and the
notes say so in their own text. Note templates, per-note narrative editing,
signature blocks and consolidation remain outstanding (Backlog 18i).

## Delivery Plan Phase 5 (Backlog 8) — Percentage tax, the whole chain

Status: **PASSING 2026-08-04.**
`supabase/tests/124_percentage_tax_chain_test.sql` (37 assertions, self-provisioned
company) closes the last unblocked accounting gap: a non-VAT Section 116 taxpayer
now computes, posts, reconciles and files its business tax.

**What was missing.** Percentage tax was calculated nowhere in PXL and never had
been. A company could be configured as non-VAT and percentage-tax registered, be
given `percentage_tax_codes`, sell all year — and produce no component, no journal
line, no tax-ledger row, no working paper and no 2551Q. The PT Return screen
filled the void by summing VAT-**exempt** sales lines in the browser, which is
wrong twice over: VAT exemption is not the percentage-tax base, and a return
computed on the client is not a return computed from the books.

**Two master-data defects were repaired with it.**
`fn_seed_company_percentage_tax_codes` seeded a row labelled "3% general" whose
`tax_code_id` pointed at **PT12-OUT (12%)**, because it took the first `pt` tax
code by code and 'PT12-OUT' sorts before 'PT3-OUT'; and where a company had no
percentage-tax ATC it attached **any** ATC — a withholding one — so the 2551Q line
would have carried an EWT code. Nothing had ever posted from those rows, so the
repair restates no book.

Section A proves the route. There is one business-tax picker and one resolver, not
a parallel stack: `fn_business_tax_codes_asof` offers the Section 116 code to a
non-VAT, percentage-tax-registered company (1), never to a VAT-registered one (2),
and never on a purchase line (3) — percentage tax is the seller's own tax, not a
component of what a supplier charges. A VAT company is refused the code outright
(4) and a code cannot be borrowed from another company (6). A Section 116 line is
legitimately VAT-**exempt** and percentage-taxable at the same time, so one call
answers for both families (5). The engine charges 3% of gross sales and leaves net
and gross untouched (7): the customer is not charged this tax.

Section B is the counter sale — 20,000 of services and 4,000 of goods. The
customer is billed 24,000 with no VAT and the shop owes 720 (8); every line stamps
the base, the resolved rate and its amount (9); the journal balances with the tax
in it (10); the tax is expensed (11) and owed (12); **the receivable is still the
24,000 the customer owes** (13); and the goods still leave stock (14) — percentage
tax changed nothing else. The ledger row carries the tax-code version, its rate,
the 2551Q ATC (15) and the company code version it came from (16), and it ties to
the payable control account at **0.00 variance** (17).

Section C repeats the act on a credit Sales Invoice through approve-and-post
(18–20), and both documents together still reconcile at 0.00 (21).

Section D is the filing artifact. The quarterly computation groups by ATC, which
is how a 2551Q is filed (22); generating the return reports 1,020.00 due (23) and
stores the ledger figures with the VAT-shaped legacy columns at zero (24); the
working paper schedules both documents behind the one number (25) and adds up to
it (26). A return may not be filed on a figure the ledger does not support (27),
may be marked final when it agrees (28), and is never silently rewritten
underneath the accountant afterwards (29).

Section F is the void. The tax is recognised on the document, so a document
that is voided must take its tax back out: the September invoice recognises
800.00 at the successor rate (35), voiding it counter-posts the ledger to nil and
the counter-row **keeps the company code version it reverses** (36), and the
quarter still ties to the General Ledger, at nil (37). `fn_reverse_tax_detail_entries`
already reversed every tax kind generically; it now stamps
`percentage_tax_code_id` on the counter-row, which it could not do before because
the column did not exist when it was written.

Section E is the statutory rate change. Section 116 fell to 1% under CREATE and
returned to 3%, so the rate is a **succession, not an edit**: a successor cannot
start while the version it replaces is still open (30), the version that computed
a filed quarter can never be edited (31), and the superseded version is refused on
a date it no longer covers (32). A May sale is taxed at 1% (33) and Q2 files on
its own quarter, leaving the filed Q1 alone (34).

**Committed evidence, separate from this file.** Three counter sales across two
quarters on a self-provisioned company, with real COMMITs: ledger rows of 450.00,
750.00 and 1,200.00 on bases of 15,000, 25,000 and 40,000; ledger-to-GL variance
**0.00** against account 2240 for the year; trial balance out-of-balance **0.00**;
Q1 filed at 1,200.00 on a base of 40,000 with a two-line working paper, Q2 draft at
1,200.00.

Not claimed: recognition is on the sales document (accrual on gross sales), not on
collections for services; a credit memo does not yet reverse percentage tax; and
nothing compels a percentage-tax-registered company to put its code on a line —
all three are recorded in the Product Backlog.

## Delivery Plan Phase 5.8 — BIR filing artifacts, on one governed path

Status: **PASSING 2026-08-04.**
`supabase/tests/125_bir_filing_artifacts_test.sql` (42 assertions, self-provisioned
company) proves that every registered filing artifact is produced by the same
three functions from the same posted ledger:

> Posted Transactions → Tax Engine → Tax Ledger → Reconciliation → Working Paper
> → Filing Artifact → Export → Filed Record

**What was there before.** Three near-identical reconciliation functions and three
more computations in JavaScript. `fn_vat_gl_reconciliation`,
`fn_wht_gl_reconciliation` and `fn_percentage_tax_gl_reconciliation` had
effectively the same body, differing only in which tax kinds they read, which
control account they compared against, that withholding excludes the `WHTREM`
remittance journal, and that VAT counts `reversed` journals while withholding does
not — four differences, three copies, and every future tax would have been a
fourth. Meanwhile the 2550Q screen computed the quarterly VAT return in the
browser by summing two review views with `reduce`, and so did the SLSP export and
the SAWT alphalist.

Section A proves that registering a form is configuration rather than code. The
registry names exactly the five artifacts this increment registers (1); a return
states which way each tax kind moves its net, so input VAT is a credit against
output VAT rather than a second liability (2); the `WHTREM` exclusion and the
journal statuses that used to separate two functions are now rows in
`ref_tax_ledger_control` (3); an unregistered form is refused rather than guessed
at (4); and one function turns a filing period into dates (5).

Section B posts the three documents everything else is read from — a 100,000
invoice to an ordinary buyer, a 50,000 counter sale to a withholding agent who
withholds 500, and a 25,000 supplier bill on which the company withholds 500 —
leaving exactly four kinds of tax in the ledger (6).

Section C is the consolidation. The VAT face returns exactly what the one
reconciliation returns (7), and so does the withholding face (8) — same rows, same
columns, same semantics, no second implementation. Every tax kind ties to its
control account at **zero variance** (9), and a reconciliation over no tax kind is
refused rather than silently empty (10).

Section D is the 2550Q generated from the books rather than the browser. It nets
18,000 output VAT against 3,000 input VAT to 15,000 payable (11); its working
paper carries the VAT-code split behind each figure (12); the per-kind summary is
stored on the artifact rather than as per-form columns, which is what lets one
table serve every form (13); and the working paper adds up to the return it stands
behind (14).

Section E runs four more artifacts through the same engine with no new code. The
1601EQ reports the 500.00 withheld from the supplier (15), grouped by ATC, which is
how the alphalist is filed (16). The SLSP lists three counterparties (17) because
the same reader groups by counterparty when the artifact says to (18), and a
listing owes nothing so it reports no payable (19). The SAWT lists the tax withheld
**from** this company per payor and ATC (20). A VAT company files an empty 2551Q
rather than an error: it owes none (21).

Section F proves percentage tax joins this engine rather than sitting beside it.
`fn_generate_pt_return` generates through the one generator (22), the 2551Q
computation reads the one working paper (23), **no per-form function reads the tax
ledger itself any more** (24), and the 1601EQ face still answers exactly as its
screen expects (25).

Section F2 is the 2550Q leaving the browser. The return projects into
`vat_returns` straight from the artifact (26), generated through the one generator
(27), reading neither of the review views the browser used to sum (28). Input VAT
carried over and VAT already paid are the accountant's to state, so they are
stated **to the RPC** and netted in the database (29), survive a regeneration that
does not restate them (30), and a negative is refused rather than quietly netted
(31). A quarter carrying all three VAT treatments on one invoice puts zero-rated
and exempt sales in their own columns, taxed at nil (32), because the working
paper carries the classification behind every figure (33) — an exempt or
zero-rated line reaches the tax ledger with a base and a zero tax. A projected
return satisfies the guard that ties it to the tax ledger (34) and is never
regenerated underneath the accountant once final (35).

Section G is the artifact as evidence. A return may not be filed on a figure the
ledger does not support (36), may be marked final when it agrees (37), and is
never silently regenerated afterwards (38). Filing records the reference and the
date (39); a filed return is immutable, so a correction is an amended return (40);
and a filed return cannot be deleted (41). The claim the whole file exists for:
**five artifacts for one quarter, all from one ledger through one engine** (42).

Not claimed: **nothing has ever been filed with the Bureau.** A `filed` status
records the accountant's own submission; PXL does not transmit. The SLSP *screen*
still aggregates its sales side in the browser — the artifact is registered and
tested, but the screen is monthly while the attachment is quarterly and its
evidence snapshot is keyed by month. 1601FQ, 2550M, QAP, 1604-E and the Books of
Accounts exports are not registered, and the other eleven `compliance_*`
working-paper tables remain empty. All recorded as Product Backlog item 8c.

## Backlog 8d — Filing Artifact Export

Status: **PASSING 2026-08-04.**
`supabase/tests/126_filing_artifact_export_test.sql` (24 assertions,
self-provisioned company) closes the last link in the compliance chain and
proves the rule that closes the architecture:

> The Filing Artifact is the system of record for compliance outputs. Every UI,
> export, snapshot, API and integration **consumes** it, and none may rebuild a
> compliance report from transactions, tax ledgers or a browser.

**What was missing.** An accountant could generate a fully reconciled 2550Q,
2551Q, 1601EQ, SLSP or SAWT — every figure tied to the General Ledger at 0.00 —
and had **no way to get it out of PXL** to key into eFPS or eBIRForms. The three
existing snapshot functions predate the artifact layer and read **source views**,
so they could not serve: using them would have rebuilt the return a second time
from a second source.

Section A proves a form's export layout is configuration. Every registered
artifact has a registered layout (1); a layout is an ordered list of artifact
fields and how each renders (2). The assertion that matters most is (3): the
`source_field` CHECK constraint names no transaction, journal, invoice, receipt
or review-view source, so a **non-conforming layout is unwritable**. The rule is
enforced by the schema rather than by review.

Section B posts a counter sale to a withholding agent — 50,000 net, 6,000 output
VAT, 500 CWT withheld — and generates the quarter's 2550Q and SAWT (4).

Section C is refusal. A draft artifact cannot be exported (5), because an export
is evidence of a figure the accountant has settled and a draft is still moving.
An unsupported format is refused rather than guessed at (6); a format the form
has no layout for is refused rather than silently empty (7); and a period with no
artifact says so rather than exporting nothing (8).

Section D is CSV. Row 0 is the header the registry declares, in its declared
order (9); the detail row carries the artifact line with decimals rendered
through the shared `fn_export_decimal` (10); and the file is one header plus one
row per artifact line (11).

Section E is DAT. It carries no header row (12) and its TIN is normalised through
`fn_export_dat_tin` (13). Assertion (14) is the point of the design: the **same
artifact line** renders as CSV and as DAT from **one layout table**, so a second
format costs seed rows rather than a second exporter.

Section F is the claim the file exists for. `fn_filing_artifact_export` reads no
transaction, tax-ledger or review source (15); it reads the filing artifact and
its lines, and that is its only source (16); and it **aggregates no figure at
all** (17) — no `SUM`, no `AVG` — because the artifact already stated every
number. An export that re-sums is an export that can disagree.

Section G is the governed evidence. The snapshot records what was exported and
from which table (18) and points at the artifact **by its own id** rather than a
synthesised key (19) — the older exports had to synthesise one because they had
no artifact to point at. The evidence holds exactly the bytes that were exported
(20), hashed for tamper evidence through the same `extensions.digest` primitive
every other snapshot uses (21), and carries the artifact totals it was taken from
(22). Re-exporting versions up rather than superseding (23). Finally: **every
compliance export this company produced came from a filing artifact** (24).

Not claimed: nothing has been filed with the Bureau. True binary `.xlsx` is not
generated — CSV opens in Excel, which is what these attachments require. When
this file was written only the 2550Q screen was wired to this path; the SAWT and
QAP screens were migrated onto it by Backlog 8e (test `127`), and the SLSP screen
remains on the legacy snapshot pending item 8c.

## Backlog 8e (i) and (iii) — the 1601EQ and the QAP on the artifact layer

Status: **PASSING 2026-08-04.**
`supabase/tests/127_ewt_qap_filing_artifacts_test.sql` (34 assertions,
self-provisioned company) covers two surfaces that computed correctly and
**recorded nothing**.

**What was wrong.** The 1601EQ screen computed through the governed engine and
then wrote `ewt_returns` by typed INSERT from the browser, so a return could be
marked filed with **no filing artifact behind it** — no working paper, nothing to
export, nothing for the export layer to consume. The QAP was aggregated in
JavaScript from `vw_ewt_summary_ap` and registered nowhere, so the alphalist
attached to the 1601EQ could not be shown to agree with it, or with the General
Ledger. The view drops reversal counter-rows, so a voided withholding left the
two disagreeing invisibly.

Section A proves registering the QAP cost configuration: it is a quarterly
listing grouped per payee and ATC (1), reading the same tax kind as the 1601EQ
and owing nothing itself (2), with both export layouts as seed rows (3). The
`source_field` CHECK still admits no transaction or tax-ledger source (4) after
gaining `atc_description` — the governed ATC description an alphalist must name.

Section B posts three vendor bills: two rents from one supplier under WC160 and
one professional fee under WC010, leaving 60,000 of income payments and 2,800
withheld in the ledger (5).

Section C is the 1601EQ. Generating the return generates the artifact the screen
never used to leave (6) and projects it into the `ewt_returns` row the screen
reads (7); the working paper adds up to the return it stands behind (8) and is
grouped by ATC with its document counts (9). Assertions (10) and (11) are the
correction this increment made to its own design: `remitted_prior` is **not** the
accountant's to state. PXL-AUD-041 had already made it a derived figure, so the
projection reads `fn_compute_ewt_remitted_prior`, and a remittance typed into the
return instead is refused rather than filed. Regenerating a draft restates it
from the same ledger and moves nothing (12). The 1601EQ is generated through the
one generator (13) and reads no ledger, journal or review source of its own (14).

Section D is the alphalist: one row per payee and ATC from the one working paper
(15); it **adds up to the 1601EQ it is attached to** (16), which is the invariant
the browser version could not offer; it owes nothing (17); and it ties to the EWT
Payable control account at zero variance (18).

Section E is the export. A draft alphalist does not leave the system (19); an
alphalist that agrees with the ledger may be marked final (20); row 0 is the
declared header (21); a payee row names the nature of payment from the governed
ATC rather than a guess (22); the same line renders as a DAT alphalist from the
same layout table (23). The exporter still reads no transaction, tax-ledger or
review source (24) and still aggregates no figure at all (25) — the ATC
description is resolved by an ordered scalar subquery precisely so that remains
literally true. The evidence row is keyed to the artifact's own id (26, 27).

Section F is the gate that migrating a screen would have walked around: a company
that is not EWT-registered cannot export a QAP (28), and that rule now keys on
what the snapshot **is** rather than on which table produced it.

Section G resolves an orphan. `fn_qap_2307_reconciliation` was called from
nowhere in `src/` and read a source view; it now reads the artifact working paper
(29). With no certificate issued, every alphalist row is unsupported and says so
(30); once the 2307 certificates are issued, every row agrees with them (31).

Section H: a projected 1601EQ satisfies the gate that ties it to the tax ledger
(32), and once final it is never regenerated underneath the accountant (33). The
file closes on its claim: the return and the alphalist attached to it are both
artifacts of one ledger (34).

Not claimed: nothing has been filed with the Bureau. The SLSP screen is outside
this test's scope — it was still monthly and browser-aggregated when `127` was
written, and moved onto the quarterly artifact on 2026-08-05 under Backlog 8e
(ii), guarded by `tests/compliance_architecture.test.ts` rather than here. The
legacy `compliance_*` working papers and `fn_snapshot_wht_export` are retired
under Backlog 8f, after their governed replacements exist.

## Backlog 8f stage 1 — the governed Reconciling Item and the artifact role gate

Status: **PASSING 2026-08-04.**
`supabase/tests/128_filing_reconciling_items_test.sql` (30 assertions,
self-provisioned company) proves the capability parity that has to exist
**before** any legacy compliance surface is retired.

**Why it exists.** 8f's objective is eliminating the second compliance
architecture, not deleting six screens, and the owner's rule is that no
functionality is removed merely to satisfy the architecture. The capability audit
found the six legacy `compliance_*` working-paper screens are the same screen six
times, and their "Generate" button is a stub that says so itself — *"Manual entry
only — GL-backed generation requires the General Ledger module"*. Their one real
capability is keying a line no ledger backs. That capability is now governed.

Section A proves it exists only through the governed path: the line table carries
read policies only, so a working-paper line cannot be written from a browser (1);
an item without its full record is refused (2); one cannot be recorded against a
working paper that does not exist (3); and a recorded item carries reason,
reference, amount and remarks (4), the user and timestamp that recorded it (5),
and an audit row through the same trigger every governed table uses (6).

Section B is the claim the design turns on, and its assertions deliberately **do
not filter by line kind**. The artifact total is what the ledger said before the
note and after it (7); every line in the working paper still sums to that total
(8) and so does its base (9); the ledger still ties to the General Ledger at zero
variance (10); the working-paper reader returns the ledger only (11); and no
journal entry was created (12). The exclusion is structural rather than
remembered: a reconciling item's amount lives in `reconciling_amount`, which no
computation reads, and a CHECK forces its tax figures to zero — so it may not
acquire a tax figure (13) nor become a generated one by changing kind (14). The
same claim is made a second way in Section G: the one reconciliation cannot see
the column at all (29), and **no function in PXL outside the four that own it
reads it** (30).

Section C: regenerating the artifact leaves the accountant's note in place (15)
and restates the ledger side exactly once (16). An explanation of a difference
survives the restatement of the figures it explains, which is the point of it.

Section D is the control regression found while scoping 8f. Every projection of
an artifact — `vat_returns`, `pt_returns`, `ewt_returns` — and all twelve legacy
working papers restrict final/filed to owner/admin; `filing_artifacts` restricted
nothing. An ordinary member now cannot declare a return final (17), though they
may still read the working paper they work on (18) and record a reconciling item
on it (19) — preparing evidence is not approving it. A draft note can be
withdrawn (20); a generated figure cannot be deleted through the note path (21).

Section E: an owner may declare the same return final (22), after which no note
may be added (23) or withdrawn (24). The working paper settles with the return.

Section F is visibility. The CSV export is one header, one generated row and one
note (25), and the note travels with the figures it explains, marked as what it
is (26). A **DAT alphalist carries no note** (27) — the Bureau ingests that file
and a note row corrupts it, so "visible on the export" is answered with "not
there" in exactly one place, deliberately. The evidence snapshot holds exactly
the bytes that were exported, note included (28).

At this evidence point no legacy screen or table had yet been retired; stage 2
below supersedes that state. FWT/1601FQ was later classified as an excluded
future extension and carries no current-product readiness weight.

## Backlog 8f stage 2 — the second compliance architecture is retired

Status: **PASSING 2026-08-04.**
`supabase/tests/129_compliance_architecture_verification_test.sql` (22
assertions, self-provisioned company) **is the verification report**, and
`tests/compliance_architecture.test.ts` (6 tests) is its screen half. The owner
asked for a report showing that one compliance architecture remains and that no
routed screen, RPC or export bypasses the governed pipeline; prose goes stale the
moment someone adds a function, so the claim is asserted on every run instead.

The claim, stated as it must be stated:

> The governed compliance architecture is complete for every implemented
> current-product compliance family. FWT/1601FQ is an excluded future extension,
> not an architecture exception or readiness gap.

**What was retired** (migration `20260804000006`, after — never before — its
replacement was reachable): the legacy PT working-paper write inside
`fn_generate_pt_return`, which was the last function writing any legacy table;
the eight VAT, EWT, 1601EQ and PT working-paper tables; and
`fn_snapshot_wht_export` with `wht_export_periods`. Four routed screens were
replaced first by `FilingWorkingPapersPage`, one governed surface serving all
four forms.

Section A verifies the first sentence. The eight tables are gone (1), and so is
the synthesised export key (2) and the legacy export function (3). **No function
anywhere in PXL still reads or writes a retired working paper** (4). The only
working-paper tables left are the four FWT ones (5). No export snapshot of a
registered form is keyed to anything but the artifact (6); no filing or export
function reads a review view (7); and **exactly one function writes a filing
artifact** (8).

Section B verifies the second sentence as a scope-boundary fact: FWT is not a
governed tax kind (9), the tax ledger will not accept an FWT row (10), and no FWT
form is registered (11). These assertions prove that the prototype does not
silently enter the current architecture. Any future Product Architecture
Amendment that adds FWT must deliberately revise this evidence.

Section C carries the two claims inherited from retired test `016` (see above),
plus the refusal of an impossible filing period (15).

Section D walks one posted sale through the whole pipeline on one company: the
working paper reads 12,000 of output VAT from the ledger (16), the artifact
states the same 12,000 (17), it ties to the General Ledger at zero variance (18),
the return projection carries it without recomputing it (19), and the exported
bytes carry the same figure (20). No reconciling item was needed to make any of
it tie (21). Assertion 22 is the file's whole purpose in one statement.

The screen half asserts what pgTAP cannot see: no page reads a retired table or
calls the retired export; the four routes render the one governed surface and the
four legacy pages are deleted rather than merely unrouted; **only the two FWT
pages remain hand-keyed**; the governed surface reads no review view and
aggregates no compliance figure in the browser; and every compliance export
surface consumes `downloadFilingArtifactExport`.

Not claimed: nothing has been filed with the Bureau. The FWT/1601FQ screens and
four tables are excluded future-extension prototypes; they do not participate in
the current product architecture, delivery plan or readiness assessment.

## Backlog 10 — a statutory rate change is a succession the product can reach

Status: **PASSING 2026-08-07.**
`supabase/tests/130_tax_reference_succession_test.sql` (34 assertions,
self-provisioned company and maintainer) with
`tests/tax_reference_maintenance.test.ts` (7 tests) as its screen half.

Test `039` already proved the **rule** — a used version's rate and identity are
frozen, so a statutory change must become a successor — and test `060` proved the
**authority**, that only a provisioned statutory-config maintainer may write and
every write is audited once with its reason. What neither could prove is that the
succession was **reachable**. RLS denies every direct client INSERT on
`tax_codes`, `vat_codes` and `atc_codes`, and the governed upserts took no
`supersedes` argument, so the only version an application could produce was an
**orphan**: a row whose `supersedes_*_id` was NULL, indistinguishable from an
unrelated code that happened to share a name. The chain existed in the schema and
in the triggers, and nowhere else. The screen matched: it posted the same id back
and rewrote the rate in place, and ATC had no maintenance UI at all.

Migration `20260807000001` adds `p_supersedes_id` to the three governed upserts
and `fn_tax_code_succeed` / `fn_vat_code_succeed` / `fn_atc_code_succeed`, which
close a window and open its successor **in one transaction** — the two halves are
not a client's to sequence, because a half-done succession leaves a code that
resolves to nothing. Each succeed function delegates both writes to its upsert,
so authority, normalization and audit are stated once. It also gives `vat_codes`
the version-rules trigger it alone lacked; `tax_codes` and `atc_codes` had
carried one since `20260713000012` and `20260713000002`.

Section 1 refuses all three successions to a non-maintainer (2–4). Section 2 is
the point of the file: a version that has priced a posted document still refuses
an in-place rate change (6), accepts the succession (7), keeps its own rate (9)
while its window closes the day before its successor's (8), and the successor
records what it supersedes (11). A March document still resolves to 12% and an
August one to 14% (14, 15) — the reason any of this exists. Both halves are
audited under the typed reason (16). Sections 3 and 4 refuse a successor that
starts on or before its predecessor (17, 18) and prove the transaction is atomic:
a colliding successor leaves the predecessor's window exactly as it was (19, 20).
Sections 5 and 6 repeat the chain for ATC and VAT, where a VAT successor must
point at the tax-code version carrying the new rate (29) because `vat_codes`
states no rate of its own. Section 7 records a link on a plain governed insert
(31, 32) and refuses one pointing at a different code (33).

The screen half asserts what pgTAP cannot see: the page writes none of the three
tables directly, calls all nine governed RPCs, offers succession rather than only
an in-place edit, sends the effective window as a field, asks
`fn_is_bir_config_maintainer()` before offering any action, shows the database's
own refusal instead of an `alert()`, and sends the reason the maintainer typed.

Not claimed: **deprecation**. `deprecated_at` / `deprecated_reason` exist on all
three tables and gate `fn_atc_code_is_current`, but no governed setter has ever
existed and none is added here; deactivation and window closure are what the
governed path offers. Not claimed: any real BIR rate change has been configured.

## Backlog 18c — the day a delivery is wrong, and a defect only a commit could show

Status: **PASSING 2026-08-07.**
`supabase/tests/131_delivery_receipt_cancellation_test.sql` (24 assertions,
self-provisioned company), `tests/delivery_receipt_cancellation.test.ts` (5 tests)
and `scripts/verify_delivery_receipt_lifecycle.mjs`, which runs **outside** a
transaction.

Test `120` walks the outbound happy path. This file walks the mis-ship. A posted
delivery could be neither cancelled nor reversed, so the cost parked in Goods
Delivered Not Invoiced could be released only by **billing** it — by invoicing a
customer who never received the goods. `fn_void_delivery_receipt` reverses the
delivery journal through `fn_reverse_posted_journal_entry`, the same reversal
every other void uses, and puts the stock back through the same shared costing
path the posting used to take it out.

The ordering rule is the substance: an invoice that already claims the delivery
must be voided **first**, because reversing the clearing balance from underneath
a live invoice would leave it taking a cost that no longer exists. A **draft**
invoice counts — it already holds the delivered line through
`uq_sil_delivery_source`. Assertions 6–9 raise a draft invoice, prove the
cancellation is refused (7), prove the refusal changed nothing (8), then void the
invoice and proceed. Assertions 10–20 are the correction itself: the goods come
back (13, 14), the weighted-average cost is undisturbed (15), the restock is its
own transaction rather than an edit of the issue (16), and Goods Delivered Not
Invoiced nets to zero (17). Assertions 21–22 close the door afterwards — one
reversal, not two, and a cancelled delivery can no longer be billed. Assertion 23
cancels a draft delivery, which writes no journal because it moved nothing.

**Two defects were found here, and neither was visible to pgTAP.**
`delivery_receipts` became a posting document on 2026-08-03 without its
2026-07-04 status guards being widened, so **`fn_post_delivery_receipt` was
refused whenever the delivery had been marked delivered in an earlier
transaction** — which is exactly what the screen does. Both the header guard and
the line guard blocked it (PXL-AUD-074). Separately, `fn_capture_cas_document_void`
erased the void reason it had just resolved whenever no reversal journal existed,
so **no draft document could be voided at all**, across twelve CAS families
(PXL-AUD-075).

pgTAP runs each file in one transaction, and both guards carry a `same_txn`
escape, so inside pgTAP they never engage: 130 test files could not see a defect
that made delivery posting unusable. Assertion 1 is structural for that reason,
and `scripts/verify_delivery_receipt_lifecycle.mjs` — five committed
transactions, `npm run verify:delivery-receipt-lifecycle` — is the behavioural
proof. **A gate that only ever sees one transaction cannot see this class of
defect**, which is the lasting lesson of this entry.

Not claimed: partial cancellation. A delivery cancels whole or not at all; a
partial return is the Customer Return path test `120` already covers. Not
claimed: FIFO restock ordering — this company costs weighted-average.

## PXL-AUD-076 — a cash sale is one event, and it now withdraws as one

Status: **PASSING 2026-08-08.**
`supabase/tests/132_cash_sale_void_atomicity_test.sql` (18 assertions,
self-provisioned company) and `scripts/verify_posting_lifecycles.mjs`, which
found the defect and now holds the claim across committed transactions.

A Cash Sale is one business event recorded as **two** documents, because that is
what the BIR expects: the CS-series sales document and the Official Receipt that
collects it. `fn_save_cash_sale` creates both in one act. **Voiding withdrew only
the invoice half.** Revenue, output VAT, COGS and inventory reversed correctly;
the receipt's `DR Cash / CR AR` journal stayed posted. Every voided cash sale
therefore left **cash overstated by the full sale**, a **phantom credit in
Accounts Receivable** for a customer who owed nothing, and a `posted` receipt
collecting a sale that no longer existed — with the trial balance still
balancing, because the surviving journal balanced perfectly well on its own.

It was reachable, not latent: the Cash Sale screen has no void action, but the
Sales Invoice screen calls `fn_void_sales_invoice` and its list filters only on
company and status, so cash sales appear there and can be voided from there.

`fn_void_cash_sale` is now the authority for the business event, and
`fn_void_sales_invoice` **delegates** to it whenever `is_cash_sale`. Routing
rather than blocking is the whole design: no screen has to know the difference,
so there is no browser-side coordination to get wrong, and the general invoice
surface cannot bypass the governed path because it *is* the governed path. One
function is one transaction, so both halves reverse or neither does. It adds no
reversal engine — both halves go through `fn_reverse_posted_journal_entry` — and
two private helpers were extracted so each rule is stated once:
`fn_reverse_receipt_core` (lifted out of `fn_bounce_receipt`, terminal state now
a parameter, because a bounced cheque and a withdrawn sale are different events
needing the same mechanism) and `fn_stamp_void_inventory_dimensions`.

Assertions 1–2 hold the design: the invoice void routes into the cash-sale path,
and the receipt-reversal core is private. The fixture then rings up a five-unit
counter sale (3–5) and voids it **through the general Sales Invoice entry point**
(6), which is the path a user actually takes. Both documents reach `cancelled`
(7, 8). Then the accounting claim, one account at a time: cash returns to zero
(9) — the assertion this file exists for — the AR bridge the cash-sale structure
creates is fully cleared (10), and revenue, output VAT and COGS follow (11–13).
Inventory returns to its pre-sale quantity and governed original cost (14, 15),
the tax ledger nets to zero for the whole event including any CWT withheld on the
collection (16), and the trial balance still balances (17). Assertion 18 refuses
a second void, so no half can reverse twice.

**Closed with it:** `fn_bounce_receipt` and `fn_void_sales_invoice` were both
**`anon`-executable**. Every historical grant was a bare `GRANT ... TO
authenticated`, and PostgreSQL grants EXECUTE to PUBLIC by default. Neither was
exploitable — both fail closed on `is_company_member` — but a destructive
financial entry point should not be reachable without a session. The `anon`
census in test `102` falls from 196 to 194.

Not claimed: percentage tax. This company is VAT-registered; the percentage-tax
reversal shares the same `fn_reverse_tax_detail_entries` path already proven by
tests `048` and `124`.

## Backlog 18b safety guard — delivered stock cannot be relieved twice

Status: **PASSING 2026-08-08.**
`supabase/tests/133_sales_invoice_delivered_stock_guard_test.sql` (18 assertions,
self-provisioned company).

The full Document Conversion Engine is not delivered. This bounded guard closes
the unsafe gap while preserving that distinction: both Sales Invoice approval
and posting pass through `fn_validate_sales_invoice_accounting_ready`, which now
refuses an unlinked stock line when a live delivered Delivery Receipt for the
same company, customer and item remains available to bill. The private
relationship helper and the SECURITY DEFINER validator are not executable by
`anon`.

The fixture first posts a Delivery Receipt and proves that a hand-entered invoice
for the delivered goods is refused without moving stock a second time or erasing
the Goods Delivered Not Invoiced balance. It then bills the delivery through the
existing `source_document_type = 'DR'` / `source_line_id` relationship and proves
stock stays unchanged while the clearing balance reaches zero. A direct invoice
for never-delivered goods and a service line remain valid. Finally, an invoice
approved before a later independent delivery is refused at posting, proving the
authoritative gate is not approval-only.

Not claimed: quotation/order carry-forward, automatic relationship creation,
quantity allocation, or the full Document Conversion Engine. The guard refuses
an unsafe invoice; the existing *Bill This Delivery* action remains the one path
that creates the governed delivery relationship.

## Purchasing quantity match and Receiving Report cancellation

Status: **PASSING 2026-08-08.**
`supabase/tests/134_purchasing_match_and_reversal_test.sql` (32 assertions,
self-provisioned company), `tests/receiving_report_cancellation.test.ts` (4
tests), and `scripts/verify_purchasing_lifecycle.mjs` (36 committed-step checks).

The quantity match is exact because no governed tolerance exists. A Receiving
Report line is checked against its own Purchase Order line, including company,
header-order and item membership, and concurrent confirmations serialize on the
order line. Confirmed quantity across multiple live receipts may not exceed the
ordered quantity. Draft and cancelled receipts contribute nothing to received
or billable progress. A Vendor Bill carrying `rr_id` may not exceed the live
received quantity per item; bills without `rr_id` remain allowed for services,
expenses and intentional bill-without-receipt processing. Relationship helpers
stay private and both progress views use invoker security so RLS remains the
tenant boundary.

The same file proves the Receiving Report correction order. A live Vendor Bill,
including a draft, blocks cancellation. After the bill is voided, cancellation
still refuses if the receipt quantity is no longer on hand and names the
shortfall. A valid weighted-average cancellation removes the received quantity
and value atomically, reverses the original journal through the shared reversal
authority, nets Goods Received Not Invoiced to zero, and reopens both Purchase
Order progress and its header status. A draft receipt cancels without a stock or
journal effect. A FIFO receipt can still be confirmed, but its cancellation is
refused with SQLSTATE `0A000` until cost-layer replay semantics are governed.

The source-contract test proves the Receiving Reports screen calls only
`fn_void_receiving_report`, sends the selected governed reason and memo, shows
the database refusal, and refreshes the open receipt plus the list. The separate
purchasing lifecycle lane commits between PO, two receipts, two bills, payment,
bill/payment correction, and both receipt cancellations; it proves partial and
second-document behavior, both over-quantity refusals, stock/value, clearing,
AP, input VAT, tax-detail reversal and a balanced trial balance across real
transaction boundaries.

Not claimed: price match or price variance. PXL has no governed tolerance,
variance account, reason/approval policy, or capitalization-versus-expense rule,
so this package does not invent one. The original Weighted-Average-only
correction boundary was superseded by the production inventory-costing authority
below; test `134` now proves FIFO receipt cancellation after its downstream issue
is corrected.

## INVENTORY-COSTING-AUTHORITY-001 — three production methods, one historical authority

Status: **PASSING LOCALLY 2026-08-08.**
`supabase/tests/135_inventory_costing_authority_test.sql` (25 assertions),
`supabase/tests/136_inventory_writer_coverage_test.sql` (17),
`supabase/tests/137_inventory_return_authority_test.sql` (14), updated production-path tests
`031`, `120` and `134`, and `scripts/verify_inventory_costing_lifecycle.mjs`
(28 checks across separately committed business steps).

The authority owns quantity and cost evidence but not GL posting. Its private
receive, issue, return, transfer and reversal functions update
`stock_balances`, immutable `inventory_transactions`, cost layers and exact
`inventory_layer_allocations`; public document RPCs delegate to it, and only the
Posting Engine/Accounting Kernel creates journals. Browser roles cannot write
the projections or execute private costing helpers.

Test `135` states each method's core arithmetic and correction contract:

- Weighted Average receives 100 @ 10 and 100 @ 14, reports 200 / 2,400 / 12,
  issues 50 for 600 and restores the original 600 rather than repricing it.
- FIFO issues 120 from 100 @ 10 plus 20 @ 14 for 1,280, stores both allocations,
  refuses source-receipt cancellation while a layer is consumed, restores those
  exact layers on issue reversal, then cancels the now-available receipt.
- Specific Identification receives three serials at different costs, selects
  Unit B for exactly its 12,000 cost, refuses wrong-warehouse and already-used
  identities, and restores Unit B itself on reversal.

The same test makes costing-method succession fail closed after activity,
confirms authenticated/anonymous clients cannot mutate costing state, and proves
the dormant IA-5/ECC `inventory_events` stream remains at zero consumers.

Test `136` drives real Posting Engine entry points: FIFO Goods Issue across two
layers, a negative FIFO Stock Adjustment at layer cost rather than standard
cost, a Specific-ID Stock Transfer that preserves serial, value and parent-layer
lineage, and a Physical Count that removes that same serial at exact cost. The
layer-versus-stock reconciliation remains zero and the journals carry the same
authoritative values.

Test `137` proves return semantics. A WAC customer return uses the original issue
rate after a later receipt changes today's pool. Partial FIFO returns restore the
original allocations deterministically and cannot exceed the source issue.
Specific ID restores the same serial. A supplier return selects its exact receipt
layer — not the oldest current FIFO layer — and refuses to fall back when that
source is missing. Production Credit Memo/Customer Return and Purchase Return
paths are separately held by tests `120` and `031`.

The committed lifecycle provisions a new company, receives WAC/FIFO/serial stock,
posts a real Delivery Receipt, and verifies line costs 600 / 1,280 / 120,
allocations, Inventory, clearing and trial balance after each commit. It voids
the delivery in a later transaction and proves exact restoration. Finally, two
real Goods Issues race for the same serial: exactly one posts, one is refused,
no layer is over-consumed, and valuation/GL/TB remain reconciled.

Classification for the intended current transaction lifecycle:

| Method | Built | Reachable | Exercised | Proven |
| --- | --- | --- | --- | --- |
| Weighted Average | Yes | Yes | Yes | Yes, locally |
| FIFO | Yes | Yes | Yes | Yes, locally |
| Specific Identification | Yes | Yes, with serial/lot selection | Yes | Yes, locally |

Not claimed: Inventory module certification, hosted migration, browser/UAT,
pilot readiness, landed cost, or backdated economic replay. IA-5/ECC remains a
separate frozen architecture with zero production consumers.
