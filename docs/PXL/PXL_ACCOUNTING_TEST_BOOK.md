# PXL Accounting Test Book

This file records expected accounting/reporting scenarios that must be executed before a finding can be marked `Retested Passed`.

How to execute seeded scenarios: `supabase start` (Docker required; non-essential services are disabled in `supabase/config.toml`), then `npm test` (alias for `supabase test db`). Tests live in `supabase/tests/*.sql` (pgTAP), self-seed inside a transaction, and roll back. `supabase db reset --local` verifies the migration chain replays on a fresh database. CI: `.github/workflows/ci.yml` runs lint/build and the full suite on a fresh database for every push/PR to `main`, so each CI run is also a fresh-replay migration check.

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

Status: Executed Passing (2026-07-02) in `supabase/tests/006_pv_ewt_partial_payment_test.sql`.

Related findings: PXL-AUD-007, PXL-DA-009, PXL-DA-010.

Scenario (VAT company; VB 2026-01-10 for 11,200.00 = 10,000.00 net + 1,200.00 input VAT):

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

Remaining under PXL-AUD-015: certificate version/supersede workflow beyond the sent/acknowledged lock.
