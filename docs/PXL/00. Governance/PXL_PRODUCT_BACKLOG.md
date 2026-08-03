# PXL Product Backlog

**Status:** Active Operational Backlog
**Authority:** Tier 3; it does not override Tier 1 rules or the central findings register
**Last Verified:** 2026-07-26
**Applies To:** Approved implementation work, missing capabilities, UX rollout, future enhancements, and deferred work
**Read When:** Planning beyond the one task selected in `AI/AI_STATE.md`
**Do Not Read For:** Finding remediation detail or fresh-session startup

## Backlog Rules

- Official defects and release blockers belong only in `PXL_END_TO_END_AUDIT_FINDINGS.md`.
- This file refers to defects by ID and never duplicates their full evidence or remediation.
- Posting changes must first be defined in `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`.
- Transaction field/source changes must remain synchronized with `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md` and `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`.
- Nothing here is authorized merely because it is listed. Work must be selected in `AI/AI_STATE.md` or explicitly approved.
- The Accounting Core Ready gate remains active; broad UX/report/dashboard rollout waits behind its security, accounting, tax, CAS, source, and regression prerequisites.

## Active Defects

The authoritative status, severity, scope, and fix are in the central register.

| Finding | Backlog Relationship |
| --- | --- |
| `PXL-AUD-055` | Critical external key-rotation dependency; not a feature backlog item. |
| `PXL-AUD-063` | BIR configuration RLS hardening; recommended next executable finding. |
| `PXL-AUD-066` | CAS historical evidence correction; blocks full regression lane. |
| `PXL-AUD-061` | Deterministic lane governance after CAS correction. |
| `PXL-AUD-053` | Sales Invoice source-backed completeness before approved-reference status. |
| `PXL-AUD-059` | Supported/deferred/unexercised workflow and table coverage. |
| `PXL-AUD-067` | Core-accounting versus operational-readiness checklist scope. |
| `PXL-AUD-060` | Login form accessibility and automation reliability. |

## Approved Implementation Work

These are long-term capabilities under the accounting-core sequence, not substitutes for active findings.

| Work | Required Outcome | Primary Authority / Dependency | Priority |
| --- | --- | --- | --- |
| Posting Engine P5.2 guard arming and enforcement certification — **Completed 2026-07-26** | Guard compile-time enforcement is enabled; non-kernel writes reject across client, RPC, helper, migration, replay, and direct-owner paths; the same six sanctioned kernels remain valid; all accounting equality suites are green. This completion does not authorize P6. | `PXL_POSTING_ENGINE_SPEC.md` §4.6/§4.6.3; migration `20260726000012`; test `102`; `p52_kernel_security_census.sql` | Completed |
| Posting Engine P6 Inventory reconciliation blocker | Before P6 can resume, govern the accounting treatment for Receiving Report inventory acquisition, purchase clearing, Vendor Credit inventory-value effects, opening inventory source/GL equality, and cost-layer consumption. Current canonical exact variances are documented in `PXL_POSTING_ENGINE_SPEC.md` §5.4.1. This row authorizes no Inventory, Posting, or canonical-data change. | Posting Engine §5.4.1; Accounting Test Book `POSTING-ENGINE-P6-INVESTIGATION-001` | Blocked |
| Account determination engine | Derive operational GL accounts from company, tax profile, item group/item, counterparty, and document type; any override is permission-gated, reason-coded, and audited. | Accounting Rules Matrix; master-data governance | High |
| **Tax Engine — architecture, consolidation, and certification** | See the dedicated scope below. Registered 2026-07-26 as a **separate governed program** when Posting Engine P4 certified the boundary around it and confirmed the engine does not exist. | Accounting Rules Matrix; tax setup specs; `PXL_POSTING_ENGINE_SPEC.md` §5.3/§5.3.1 | High |
| Master-data governance | Model and permission every master required by claimed transactions; do not expose free-text substitutes for missing governed dimensions. | Principles; transaction field-source matrix | High |
| Reconciliation suite | Prove AR=AR control, AP=AP control, inventory=inventory GL, assets=asset GL, FS=TB, and tax ledgers=tax controls with drillable variances. | Existing VAT/WHT and as-of reconciliation patterns | High |
| CI schema-type drift gate | Regenerate Supabase types against a migrated DB and fail when `src/lib/database.types.ts` differs. | `npm run gen:types`; CI | High |
| Governed full regression lanes | Name fresh-schema, canonical-seeded, hosted-safe read-only, and hosted UI lanes with explicit prerequisites/results. | `PXL-AUD-061`; `PXL-AUD-066` | High |

### Tax Engine — consolidation DELIVERED 2026-08-03; certification outstanding

Registered 2026-07-26 as a future program. **Items 1–6 were delivered by Delivery Plan Phase 4 (PAD-001) in migration `20260803000001_tax_engine_calculator.sql`.** Evidence: `supabase/tests/117_tax_engine_calculator_test.sql` (31 assertions, self-provisioned company) and the re-scoped `supabase/tests/090_posting_engine_p4_tax_boundary_test.sql`.

The starting position recorded here said seven duplicated calculators. The live catalog said **eleven** — the seven save routines plus `fn_validate_payment_voucher_line_ewt`, `fn_validate_receipt_line_cwt`, `fn_apply_vendor_bill_line_ewt_profile` and `fn_apply_cash_purchase_line_ewt_profile`. All eleven were migrated. The engine was a **consolidation**, as predicted, not a rescue.

| # | Scope item | Status |
| --- | --- | --- |
| 1 | Consolidate the duplicated document-save tax calculations | ✅ All eleven, not seven. VAT-inclusive treatment existed in only one and is now shared by all. |
| 2 | Define one effective-dated authoritative tax calculator | ✅ `fn_calculate_tax`, for **both** tax families. Withholding was effective-dated by PAD-001 (test `117`). VAT was **not** — it resolved `WHERE vc.id = <id>` and ignored active/deprecated/effective state, so a superseded version still computed tax and an unresolvable code silently became exempt at 0%. Closed 2026-08-03 by `20260803000002_vat_effective_date_resolution.sql`: `fn_resolve_vat_code` is now the one place a VAT code's validity is decided, and the engine, the line/header trigger backstop and the `fn_vat_codes_asof` picker all ask it. Asserted by test `118` across a deprecate-and-succeed VAT rate change. |
| 3 | Produce a real Tax Component output | ✅ `public.tax_component` composite; `fn_calculate_tax` returns `SETOF` it. |
| 4 | Support the currently implemented behaviours | ✅ for classification, rate lookup, taxable base, inclusive/exclusive, exempt and zero-rated, rounding, VAT and EWT/CWT/FWT withholding. Reversal provenance was already Tax-Ledger-owned and is unchanged. |
| 5 | Migrate the save-layer functions with byte-for-byte accounting proof | ✅ Carried by test `090` assertions 17–43/45/46, which passed **unchanged** across the migration. |
| 6 | Separate `fn_save_cash_sale` tax calculation from its posting | ✅ It no longer computes any tax. Closing it also fixed a real defect: it had been resolving CWT rates with no active/deprecation/effective-date filter. |
| 7 | Re-run the full P4 Tax Component Contract certification | ☐ **Outstanding.** Test `090` now certifies the *post-engine* boundary; it does not discharge the frozen contract certification in `PXL_POSTING_ENGINE_SPEC.md` §5.3. |
| 8 | **Percentage tax calculation** *(added 2026-08-03)* | ☐ **Outstanding, and it was never in scope for any calculator — PT is computed nowhere in PXL and never has been.** A non-VAT, PT-registered company's sales produce no percentage tax, so `percentage_tax_codes` and the PT review/return surfaces have no source. **Build the whole chain at once or not at all:** Sales Invoice or Cash Sale line → selected PT business-tax code → PT tax component → PT liability posting → PT tax ledger/reconciliation → working paper → 2551Q filing artifact. A dormant PT branch in `fn_calculate_tax` with no consumer is explicitly **not** authorised — that is the mistake IA-5/ECC already paid for. PT codes must be offered to a non-VAT/PT-registered company and **not** to a VAT company, through the same picker/validation route as VAT (`fn_vat_codes_asof` / `fn_resolve_vat_code`), not a parallel one. **The 8% income-tax election is not an invoice tax code** — it belongs in the taxpayer compliance profile and the income-tax computation, and must not become a selectable line treatment. **Dependency:** the first real PT document consumer *and* its posting path, together. **Timing:** Delivery Plan Phase 5 flows. Cash Sale posting, its former blocker, closed 2026-08-03. |
| 9 | **Front-end preview through the engine** *(added 2026-08-03)* | ☐ Outstanding. Forms still price lines client-side for preview. `fn_calculate_tax` is authenticated-executable precisely so a form can stop doing that; no form calls it yet. The pickers now read `fn_vat_codes_asof`, so the reference half of this item is done; the arithmetic half is not. |
| 10 | **Governed tax-code maintenance screen** *(added 2026-08-03)* | ☐ Outstanding, and it is the **prerequisite for any real tax maintenance**. Add/edit-through-succession/deprecate/activate for ATC, VAT and tax codes over the existing MDP-01 secured RPCs (`fn_atc_code_upsert`, `fn_atc_code_set_active`, `fn_vat_code_upsert`, `fn_vat_code_set_active`, `fn_tax_code_upsert`, `fn_tax_code_set_active`, gated by `fn_can_maintain_tax_reference`). Must not bypass those permissions or the effective-date/overlap/immutability rules — edit means *close the current window and start a successor*, never an in-place rate change. **Dependency:** none technically; the RPCs and the version guards already exist and are tested (`039`, `033`, `118`). **Timing:** before the first real BIR rate change has to be configured, i.e. before pilot. Supersedes the "VAT/PT rate-version admin UI" row under Future Enhancements. |
| 11 | **Effective-dated company tax profile** *(added 2026-08-03)* | ☐ Outstanding. **The gap:** `companies.tax_registration` is one scalar (`vat`/`non_vat`/`exempt`) with no history, so a company that registers for or de-registers from VAT mid-year has no profile to resolve against on a document date; validating a historical document uses today's registration. **Smallest fix:** a `company_tax_registrations(company_id, tax_registration, effective_from, effective_to)` history table with the same overlap/succession guards the tax masters already use, `companies.tax_registration` kept as the current-value projection, and `fn_company_tax_registration_asof(company, date)` changed to read it. That seam already exists and is the only tax-profile read in VAT validation, so **nothing else changes**. Test `118` assertion 25 pins the gap and must be revised when it closes. **Dependency:** none. **Timing:** before onboarding any company whose registration changes within a filed period. |
| 12 | **Configurable TWA default ATCs** *(added 2026-08-03)* | ☐ Outstanding. `fn_twa_ewt_atc_asof` hardcodes goods → `WC158` @1% and services → `WC160` @2%. The *lookup* is already effective-dated and fails closed, but the mapping itself is code. Replace with an effective-dated configuration mapping line kind → ATC. **Dependency:** item 10 (there must be a governed screen to maintain the mapping). **Timing:** with or after item 10. |
| 13 | **One governed withholding variance tolerance** *(added 2026-08-03)* | ☐ Outstanding. The ₱0.02 tolerance that reconciles a supplied withholding amount against the ATC-computed amount is repeated as a literal across the save and validation routines. Move it to one tax-policy configuration value. **Dependency:** none. **Timing:** low priority — the literal is consistent today; do it when a company needs a different tolerance or when the routines are next touched. |
| 14 | **Tax-rate precision beyond two decimals** *(added 2026-08-03)* | ☐ Outstanding and **deliberately not scheduled.** `tax_codes.rate` is `NUMERIC(6,2)`. No Philippine rate in use needs more. Raise precision only when an actual requirement appears; changing it early is a migration on a used, immutable-after-use column for no benefit. **Dependency:** a real requirement. |
| 15 | **Behavioural tax classifications stay in code** *(added 2026-08-03)* | ☐ **Closed as a decision, not as work.** `regular`/`zero_rated`/`exempt` change the arithmetic, not just a label, so they remain code-controlled constraints rather than configuration. Revisit only if the BIR introduces a fourth behaviour. |
| 16 | **Configurable descriptive variance reasons** *(added 2026-08-03)* | ☐ Outstanding and **deliberately not scheduled.** Reason text in tax variance messages is descriptive only and drives no behaviour. Make it configurable only when a real business need appears. |
| 17 | **Stamp the resolved tax version on the posted line and the ledger** *(added 2026-08-03)* | ◐ **Withholding half delivered for sales lines 2026-08-03.** `sales_invoice_lines.withholding_atc_code_id / _base / _rate / _amount` now carry the exact ATC version, rate, base and amount the engine resolved, and Cash Sale's per-ATC `cwt_receivable` rows read the stamped rate — which is also what keeps the posting layer from reading the ATC master. **Still outstanding:** the VAT half. `tax_detail_entries.tax_code_id` and `tax_rate` are left NULL by the VAT writers; only `vat_code_id` is stored. The version *is* recoverable today because `vat_codes.tax_code_id` and `tax_codes.rate` are frozen after use, so this is evidence convenience rather than a correctness gap — but the long-term target is that a posted tax component explains itself without re-resolving configuration: code, version id, rate, classification, base, amount, document date. Doing it touches all eight tax-ledger writers. **Dependency:** none. **Timing:** with the Phase 5 filing work, when a working paper needs the rate on the row. |
| 18 | **Roll the per-line tax model to the remaining documents** *(added 2026-08-03)* | ☐ Outstanding. Business Tax and Withholding Tax are per line on Cash Sale. Sales Invoice, Vendor Bill, Cash Purchase, Vendor Credit, Payment Voucher and Check Voucher still carry withholding at header or profile level, so those documents cannot mix goods and services under different ATCs. The columns, the engine call shape and the `receipt_lines.cwt_source` pattern all exist and are proven by test `119`; the work is applying them per document with its own posting and evidence path. **Dependency:** none technically. **Timing:** with each document's Phase 5 flow proof — do not do it as a sweep divorced from a workflow. |
| 18b | **Generalise Document Conversion for the sales chain** *(added 2026-08-03)* | ☐ Outstanding, and now **load-bearing**. Billing a delivery must carry the `source_document_type = 'DR'` / `source_line_id` link, because that link is what stops `fn_post_sales_invoice` relieving stock a second time. Today the only path that creates it is "Bill This Delivery" on the Delivery Receipt. An invoice typed by hand for goods already delivered will relieve the stock again and leave Goods Delivered Not Invoiced uncleared. **Dependency:** Delivery Plan Phase 5 item 5 (Document Conversion). **Timing:** with that item, or sooner if a pilot user is expected to invoice from the Sales Invoice screen rather than from the delivery. Until then the Delivery Receipt is the documented billing entry point. |
| 18c | **Delivery Receipt cancellation and reversal** *(added 2026-08-03)* | ☐ Outstanding. A posted delivery can be neither cancelled nor reversed: `fn_post_delivery_receipt` is idempotent and the RLS update policy already excludes `delivered`, so nothing is silently wrong, but a mis-shipped delivery has no correction path and its clearing balance cannot be released except by billing it. Sales Invoice void already reverses its own relief. **Dependency:** the Correction/Void engine pattern the other documents use. **Timing:** before pilot — a real warehouse will mis-ship. |
| 18d | **Period close and year-end roll-forward** *(added 2026-08-03)* | ☐ Outstanding, and now the **largest remaining accounting-cycle gap**. Nothing rolls revenue and expense balances into retained earnings at year end. The Statement of Financial Position balances mid-year only because the governed `current_year_earnings` line computes undistributed profit from the income-statement accounts; a company entering its second fiscal year would show the prior year's profit in that line instead of in Retained Earnings. `CLOSE` is already a registered posting source type. **Dependency:** none technically — the posting entry point and the statement lines both exist. **Timing:** before a pilot client's first year end, and before comparative statements mean anything. |
| 18e | **Comparative periods and statement notes** *(added 2026-08-03)* | ☐ Outstanding. `fn_financial_statement_report` returns opening/movement/closing for one period; a comparative statement needs the same lines for a prior period side by side, and a signed statement needs note disclosures. The Comparative Financial Statements screen still computes its own figures. **Dependency:** item 18d for the comparatives to be meaningful across a year boundary. **Timing:** with the first real statement sign-off. |
| 18f | **Governed FS structure maintenance screen** *(added 2026-08-03)* | ☐ Outstanding. `fs_structure` and `account_fs_map` are seeded with a governed default and can be re-mapped by SQL — test `121` proves a re-mapping re-presents the statement with no code change — but no UI drives it, so a company cannot re-present its own accounts. Mirrors the tax-code maintenance screen (item 10). **Dependency:** none. **Timing:** before a pilot client needs a presentation that differs from the default. |
| 19 | **Full Lines-workspace line detail** *(added 2026-08-03)* | ☐ Outstanding. The agreed line contract is: core (item, description, qty, UOM, price, discount, amount), inventory/operations (warehouse, location, lot/serial, movement type, delivery/receiving reference), dimensions (branch, department, cost center, project, functional entity), accounting and tax (account, business tax code, withholding tax code, taxable base, generated components, line total) and traceability (source document, remarks) — all reachable inside the Lines tab through expandable line details, without the user moving between document tabs. Cash Sale now accepts warehouse, dimensions, accounts and both tax codes at the database boundary and exposes warehouse plus both tax codes in the grid; lot/serial, movement type and the expandable detail panel are not built. **Dependency:** the shared workspace line-detail pattern. **Timing:** with the transaction workspace rollout, per document. |

## UX Rollout

The UI architecture rollout is complete for the 41 implemented transaction surfaces. `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md` is the sole layout/visual authority and `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md` is the sole content-variation authority. Sales Invoice is an implementation, not an architecture dependency.

Future transaction UI work must add the route to the executable coverage registry, preserve business controls, compose the shared workspace, and run the full route/screenshot/zoom/theme validation. Field-source and accounting qualification remains separate backlog work.

| Work | Required Outcome | Readiness |
| --- | --- | --- |
| Standard transaction layout | Maintain one fluid workspace architecture without erasing transaction-specific rules. | Implemented on 41 surfaces; future routes use the same gate |
| Shared financial summary | Server-authoritative totals and consistent commercial/inventory/accounting presentation per transaction type. | SI specification exists; shared contract not rolled out |
| Tax impact panel | Tax-detail rows, ATC/rates, certificate/export relationships, and reconciliation status with drillback. | Ledger sources exist; shared UX pending |
| Posting validation panel | Explain company, branch, period, series, approval, master, tax, and account blockers before action. | Readiness primitives exist; convergence pending |
| Universal drilldown/drillback | Report → GL → JE → source → line/supporting document and back with preserved filters/context. | Trace contracts exist; universal linked UX pending |
| Dimension summary | Show governed Branch/Department/Cost Center and later approved dimensions, including provenance/defaulting. | Existing SI slice partial; missing masters explicit |
| Transaction/audit timeline | Present governed lifecycle events and supporting row audit as one source story. | Core evidence UI exists; richer timeline future |
| Customer/supplier insights | Show balances, aging, open documents, tax profiles, and certificate history at capture time. | Data dispersed; aggregation endpoint/panel missing |

## Missing Features

Missing means absent or not proven as a complete supported workflow; it does not automatically mean a defect.

- Banking transactions and reconciliation canonical workflows.
- Fixed-asset acquisition through disposal/impairment/transfer with FA-to-GL reconciliation.
- Customer and purchase returns plus debit/supplier debit memo coverage.
- Approval-instance execution and separation-of-duties UI evidence.
- Amortization, recurring journal, and revenue-recognition schedule execution.
- Statutory return/working-paper generators and CAS export artifacts not covered by current canonical data.
- Project, Location, and Functional Entity masters and policies.
- Payroll engine, statutory deductions, confidentiality, approval, payment, correction, and tests.
- Payment-method settlement mappings and method-specific references such as cheque or e-wallet identifiers.

## Future Enhancements

| Enhancement | Scope / Guardrail | Priority |
| --- | --- | --- |
| VAT/PT rate-version admin UI | Guided close-current/start-successor flow; database effective-date rules remain authoritative. **Now tracked as Tax Engine scope item 10** (one screen for ATC, VAT and tax codes over the existing secured RPCs); do not schedule this row separately. | Medium |
| Snapshot hash verification and exact re-download | Recompute SHA-256 over frozen evidence and regenerate the exact recorded file. | Medium |
| TanStack Query adoption | Only high-revisit dashboards/registers/reports and shared reference reads when next touched; no mass refactor. | Medium |
| React Hook Form + Zod | Complex line-item forms only; client validation mirrors but never replaces server authority. | Medium |
| Shared company reference-data hooks | Extract within a touched domain cluster with zero behavior change and typed queries. | Medium |
| Large-form performance work | Profile 50+ line scenarios before memoization or state architecture changes. | Low |
| Zustand decision | Remove while unused; re-add only if cross-page state outgrows existing context. | Low |

## Deferred Work

The following wait until the Accounting Core Ready gate is cleared or an explicit task authorizes a narrow prerequisite:

- additional transaction workspace rollout;
- report pilots and broad report-workspace conversion;
- dashboards and management visualization expansion;
- client portal;
- AI/automation features;
- campaign, opportunity, and industry masters; and
- application-wide frontend state/form rewrites.

## Graduation Rule

When work is scheduled, `AI/AI_STATE.md` names one bounded task and its governing documents/tests. If implementation reveals a verified defect, add it only to the central findings register. When an enhancement ships and is validated, update the relevant governing specification and remove or revise its backlog row rather than appending session history.
