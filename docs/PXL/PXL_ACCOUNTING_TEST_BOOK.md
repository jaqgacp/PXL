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
| 8 | Owner directly UPDATEs a second SI to `approved` | Rejected identically: trigger-based enforcement catches RPC shortcuts. |
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

Status: Executed Passing (2026-07-03) in `supabase/tests/016_wht_export_snapshots_test.sql`.

Related findings: PXL-DA-015 (report provenance, fourth slice).

Scenario (VAT company; WC140 2% ATC; Q1 2026 books: OR with 224.00 CWT on an 11,200.00 gross collection, PV with 100.00 EWT on a 5,000.00 basis):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Reconcile Q1 withholding | `fn_wht_gl_reconciliation`: `cwt_receivable` 224.00 = CWT Receivable GL movement, `ewt_payable` 100.00 = EWT Payable GL movement, variance 0 for both. |
| 2 | Read the SAWT source view | `vw_cwt_summary_ar` is ledger-backed (`tax_kind = 'cwt_receivable'`, reversed pairs excluded) and exposes the gross income payment (11,200.00 = payment + CWT), not the net collection. |
| 3 | Export SAWT for Q1 | `fn_snapshot_wht_export` creates an `exported` v1 snapshot: period 2026-01-01..2026-03-31, 64-character SHA-256 source hash, frozen per-customer income payments and CWT withheld. |
| 4 | Export QAP for Q1 | Separate `exported` v1 snapshot with frozen per-supplier tax withheld and detail rows from `vw_ewt_summary_ap`. |
| 5 | Re-export QAP for the same quarter | v2 on the same deterministic logical source id — export history is versioned, never overwritten. |
| 6 | Attempt direct snapshot writes as `authenticated` | Direct INSERT rejected (42501); UPDATE/DELETE policies filter every row, so the snapshot survives untouched. |
| 7 | Request an unknown report type or quarter 5 | Rejected with explicit errors. |
| 8 | Post a manual JE crediting EWT Payable without tax detail | QAP export is blocked (`does not reconcile to GL account`); SAWT export still succeeds because its own control account (CWT Receivable) still reconciles. |

Notes:

- SAWT previously aggregated `receipt_lines` through `sales_invoices` in the browser, so cash-sale CWT rows never reached the alphalist and income payments were net of CWT; the page now reads `vw_cwt_summary_ar` and both pages snapshot via `fn_snapshot_wht_export` before producing a CSV.
- Same remittance caveat as VAT-RECON-001: legitimate 0619-E/1601EQ remittance JEs on the withholding control accounts surface as variance until a controlled remittance flow exists.

## CAS-EXPORT-SNAP-001 - CAS DAT Export Snapshots and Server-Attested Export Log

Status: Executed Passing (2026-07-03) in `supabase/tests/017_cas_export_snapshots_test.sql`.

Related findings: PXL-DA-015 (report provenance, fifth slice); full CAS enforcement remains PXL-DA-019.

Scenario (VAT company; February 2026 books: SI 10,000 + 1,200 output VAT, OR with 224.00 CWT, VB 5,000 + 600 input VAT, PV with 100.00 EWT):

| Step | Action | Expected Behavior |
| ---- | ------ | ----------------- |
| 1 | Generate the SLSP DAT extract | `fn_snapshot_cas_export` creates an `exported` v1 `CAS_SLSP` snapshot (period 2026-02-01..2026-02-28, 64-character SHA-256 hash) and writes the `cas_export_log` row itself: server-attested row count, `generated_by`, and `snapshot_id` link. |
| 2 | Compare the RPC response to the snapshot | The rows returned to the caller are exactly the frozen `export_rows` in the snapshot payload — the downloaded file is provably the hashed payload. |
| 3 | Generate RELIEF and alphalist extracts | Separate `CAS_RELIEF` / `CAS_QAP` snapshots freeze the VB input VAT row (600.00) and PV EWT row (100.00). |
| 4 | Generate the GL extract | `CAS_GL` snapshot freezes every GL line of the period and records the debit=credit balance check in its reconciliation payload; returned `row_count` matches the returned rows. |
| 5 | Re-generate SLSP for the same month | v2 on the same deterministic logical source — export history is versioned, never overwritten. |
| 6 | Attempt a direct `cas_export_log` insert as `authenticated` | Rejected (42501): the log is RPC-only evidence. |
| 7 | Request an unknown report type or blank file name | Rejected with explicit errors. |
| 8 | Post a manual JE crediting the output VAT control, then re-export | SLSP extract is blocked (`does not reconcile`); alphalist and GL extracts still succeed — gates are per-report. |

Notes:

- The page previously assembled CSVs in the browser and inserted its own `cas_export_log` rows (client-computed row counts, no hash). `CASDATFileGenerationPage` now renders the file from the RPC's frozen rows.
- The extract is still CSV-shaped; the true BIR DAT record layout is PXL-DA-019 scope.
