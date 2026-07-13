# PXL Accounting Test Book

This file records expected accounting/reporting scenarios that must be executed before a finding can be marked `Retested Passed`.

How to execute seeded scenarios: `supabase start` (Docker required; non-essential services are disabled in `supabase/config.toml`), then `npm test` (alias for `supabase test db`). Tests live in `supabase/tests/*.sql` (pgTAP), self-seed inside a transaction, and roll back. `supabase db reset --local` verifies the migration chain replays on a fresh database. CI: `.github/workflows/ci.yml` runs lint/build and the full suite on a fresh database for every push/PR to `main`, so each CI run is also a fresh-replay migration check.

Report-page adoption is governed by `docs/PXL/PXL_STANDARD_REPORT_WORKSPACE.md`. Any report marked production-ready under that standard must have evidence for its accounting purpose, authoritative source data, filters, date basis, posting-state basis, totals, reconciliation target, drilldown/drillback path, export metadata, snapshot requirements where applicable, permissions, known limitations, and performance-sensitive scenarios. Visual conformance alone is not sufficient for accounting, tax, compliance, or reconciliation reports.

The active production-readiness gate is `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md`. Any item marked **PXL Accounting Core Ready** must have engine-level evidence for posting source locking, lifecycle transitions, JE balance, period locks, numbering, source-to-journal traceability, journal-to-source traceability, reversal/void/cancel behavior, tax-detail posting/counter-rows, cross-company denial, master-data validation, and effective-dated tax-rule resolution where applicable.

`docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md` defines the expected accounting behavior and required test scenarios for each transaction type. When a transaction row is added or changed there, this test book must gain matching positive and negative scenarios before the transaction can be marked production-ready.

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

## WHT-EXPORT-SNAP-001 - SAWT/QAP Export Snapshots and WHT/GL Reconciliation

Status: Executed Passing (updated 2026-07-13) in `supabase/tests/016_wht_export_snapshots_test.sql` (19 assertions).

Related findings: PXL-DA-009, PXL-DA-015 (report provenance, fourth slice).

Scenario (VAT company; WC140 2% and WC010 10% ATCs; Q1 2026 books: OR with CWT, PV EWT, and a same-supplier second PV under a different ATC):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Reconcile Q1 withholding | `fn_wht_gl_reconciliation`: `cwt_receivable` 224.00 = CWT Receivable GL movement, `ewt_payable` 100.00 = EWT Payable GL movement, variance 0 for both. |
| 2 | Read the SAWT source view | `vw_cwt_summary_ar` is ledger-backed (`tax_kind = 'cwt_receivable'`, reversed pairs excluded) and exposes the gross income payment (11,200.00 = payment + CWT), not the net collection. |
| 3 | Export SAWT for Q1 | `fn_snapshot_wht_export` creates an `exported` v1 snapshot: period 2026-01-01..2026-03-31, 64-character SHA-256 source hash, frozen per-customer income payments and CWT withheld. |
| 4 | Export QAP for Q1 | Separate `exported` v1 snapshot with frozen detail rows from `vw_ewt_summary_ap`; payee summary rows use supplier + ATC + nature + rate granularity. |
| 5 | Re-export QAP for the same quarter | v2 on the same deterministic logical source id — export history is versioned, never overwritten. |
| 6 | Add a second PV for the same supplier using WC010 | QAP snapshot keeps two payee rows: WC010 10,000.00 / 1,000.00 and WC140 5,000.00 / 100.00, instead of collapsing the supplier into one mixed-ATC row. |
| 7 | Generate Form 2307 for the quarter | Issuance lines use the same supplier + ATC grouping as QAP; the QAP snapshot includes `form2307_reconciliation` rows with zero variance and `is_reconciled = true`. |
| 8 | Attempt direct snapshot writes as `authenticated` | Direct INSERT rejected (42501); UPDATE/DELETE policies filter every row, so the snapshot survives untouched. |
| 9 | Request an unknown report type or quarter 5 | Rejected with explicit errors. |
| 10 | Post a manual JE crediting EWT Payable without tax detail | QAP export is blocked (`does not reconcile to GL account`); SAWT export still succeeds because its own control account (CWT Receivable) still reconciles. |

Notes:

- SAWT previously aggregated `receipt_lines` through `sales_invoices` in the browser, so cash-sale CWT rows never reached the alphalist and income payments were net of CWT; the page now reads `vw_cwt_summary_ar`, and both SAWT/QAP downloads are generated from the immutable snapshot payload returned by `fn_snapshot_wht_export`.
- QAP snapshots include `form2307_reconciliation`, produced by `fn_qap_2307_reconciliation`, so auditors can compare active non-superseded 2307 issuance lines to QAP rows at supplier + ATC + nature + rate granularity.
- Same remittance caveat as VAT-RECON-001: legitimate 0619-E/1601EQ remittance JEs on the withholding control accounts surface as variance until a controlled remittance flow exists.

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

Status: Not Yet Implemented. Related finding: PXL-AUD-043.

| Step | Transaction | Expected Behavior |
| ---- | ----------- | ----------------- |
| 1 | Cash purchase of services from an EWT-subject supplier with ATC + explicit net base | Posts DR expense/input VAT, CR cash (net of EWT), CR EWT payable; ewt_payable tax detail row written. |
| 2 | Cash purchase to an EWT-subject supplier with zero EWT | Warned or blocked per policy. |
| 3 | Quarter 2307/QAP | Include the cash-purchase withholding. |

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

## CAS-E2E-DRAFT-027 - Held-Out CAS Draft Scenario

Status: Held Out Draft (not trusted baseline). File present at `supabase/tests/027_cas_end_to_end_controls_test.sql`; see `PXL_ACCOUNTING_CORE_READINESS.md` for the held-out draft list.

Notes:

- This draft belongs to the excluded `20260710000005_cas_numbering_void_dat_controls.sql` CAS lane and is not part of the production-ready baseline.
- The trusted CAS evidence path is covered by later safe slices: `supabase/tests/030_document_numbering_registry_test.sql`, `supabase/tests/031_posting_runtime_repairs_test.sql`, and `supabase/tests/032_cas_numbering_void_evidence_test.sql`.

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
