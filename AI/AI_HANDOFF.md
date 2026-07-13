# AI Handoff

Last updated: 2026-07-13 (session 88 - cash-purchase EWT slice of PXL-AUD-043 implemented)

## Active Priority (session 88 - cash-purchase EWT)

Under **PXL Accounting Core Ready** (DEC-017), session 88 implemented the cash-purchase slice of **PXL-AUD-043** with `supabase/migrations/20260713000015_cash_purchase_ewt.sql` + `supabase/tests/042_cash_purchase_ewt_test.sql` (CASH-PURCHASE-EWT-001, 10 assertions). Cash purchases now carry line EWT ATC/base/amount/income nature, validate against active EWT ATCs and company EWT profile, store `total_ewt_amount` separately, treat `cash_purchases.total_amount` as net cash paid, post DR expense/input VAT and CR EWT payable/net cash, and write source-line `ewt_payable` tax-detail rows for QAP/2307 evidence. `CashPurchasesPage` now loads supplier EWT defaults and active ATCs, captures supplier TIN, shows EWT columns, and previews EWT payable.

Verification completed for session 88: held-out-safe `supabase db reset --local`; focused test 042 passed 10/10; neighbor tests 015/024/028/038 passed 88/88; full trusted pgTAP passed **761/761 across 41 files** with held-out test 027 aside/restored; `npm run gen:types` and trusted-baseline schema summary regenerated (248 functions / 20 views / 152 tables / 252 triggers); `npm run lint`, `npm run build`, `scripts/check_docs_consistency.sh`, `git diff --check`, and `git diff --cached --check` passed. Hosted Supabase is synced through `20260713000015` with the two held-out draft migrations excluded/restored checksum-clean. The CLI emitted the known pg-delta cache warning after applying, but `supabase migration list --linked` confirmed local = remote through 15.

AUD-043 remains **In Progress**, not closed: customer advances with CWT and supplier down-payments with EWT still need a governed advance/down-payment document policy and later SI/VB application mechanics.

## Prior Priority (session 87 - semantic transaction lifecycle events)

Under **PXL Accounting Core Ready** (DEC-017), session 87 closed **PXL-DA-016** with `supabase/migrations/20260713000014_transaction_events.sql` + `supabase/tests/041_transaction_events_test.sql` (TRANSACTION-EVENTS-001, 14 assertions). The new governed `transaction_events` table is RLS-scoped and application SELECT-only; internal SECURITY DEFINER helpers and triggers write semantic lifecycle evidence for posting/reversal, registered source status changes, approval instances, and report snapshots. `fn_record_posting_event` now preserves legacy `sys_audit_logs` posting_event rows while linking them to the semantic transaction event. Hosted Supabase is now synced beyond this point through `20260713000015`.

## Prior Priority (session 85 — accounting-core implementation lane)

Under **PXL Accounting Core Ready** (DEC-017), session 85 closed **PXL-DA-010** by extending the ATC effective-date/version release pattern to VAT/percentage-tax codes. Migration `supabase/migrations/20260713000012_tax_code_effective_date_governance.sql` + test `supabase/tests/039_tax_code_effective_date_governance_test.sql` (TAX-CODE-VERSION-001, 17 assertions): `tax_codes` (VAT/PT rate holder) and `vat_codes` (classification/mapping) now carry effective-from/to + deprecation/supersession columns, version-aware uniqueness `(code, effective_from)`, an overlap + successor-integrity guard, `fn_tax_code_used`/`fn_vat_code_used` usage predicates, history guards freezing rate/identity/effective-start once used (and blocking deletes of used codes), and `fn_tax_code_version_asof`/`fn_tax_code_is_current` resolvers. No heavy VAT/PT posting RPC changed — historical stability comes from used-version immutability + deprecate-and-succeed, so a statutory rate change spawns a NEW successor version while every posted line keeps its frozen rate.

**Note — earlier state was stale:** sessions 78–84 (not captured in the prior session-77 snapshot) already closed **AUD-041**, the **AUD-034** residue, **DA-009**, **DA-019**, **AUD-037**, and **AUD-042** via migrations `20260713000005`–`20260713000011`. The authoritative status is the Findings Status Index in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **58 Retested Passed / 9 In Progress / 5 Open (72), no Criticals open**. Session 86 closed **PXL-AUD-016** and **PXL-AUD-013 + PXL-DA-014** (`20260713000013`, test 040). Session 87 closed **PXL-DA-016** (`20260713000014`, test 041). Session 88 implemented the cash-purchase slice of **PXL-AUD-043** (`20260713000015`, test 042), hosted-synced; AUD-043 remains In Progress for advances/down-payments.

**Commit / push status (session 85):** **committed as `d39e1a5` on `main`** ("Add tax code effective-date governance and update audit docs") — migration `20260713000012`, test `039`, doc updates (findings, test book, state/handoff/queue), and regenerated `src/lib/database.types.ts` + schema summary. Hosted Supabase is now synced beyond this point through `20260713000015`. The three held-out draft files remain tracked but excluded from trusted replay/push evidence.

**Next fix:** finish the remaining PXL-AUD-043 advance/down-payment policy slice or continue with PXL-AUD-040 (per-month Form 2307 breakdown), then AUD-044/046/047/049 and remaining In-Progress coverage/report items.

Third fix — `supabase/migrations/20260713000004_cm_vc_aware_overapply_guards.sql` + `supabase/tests/035_cm_vc_aware_overapply_test.sql` (CM-VC-OVERAPPLY-001, 6 assertions): the `fn_save_receipt`/`fn_save_payment_voucher` over-apply guards now net applied credit memos (AR) and non-reversed vendor-credit applications on open/applied vendor credits (AP) from the invoice/bill outstanding, mirroring `fn_ar_aging_asof`/`fn_ap_aging_asof` (scalar subqueries so the two credit sources don't fan out). Test 004 stays green.

**Next fix:** AUD-041 (controlled EWT remittance / CWT application flow — Large; unblocks SAWT/QAP exports and the Critical DA-009), then AUD-037 (withholding basis policy — needs a DEC).

Second fix — `20260713000003_settlement_total_line_authority.sql` + test 034 (8 assertions): `fn_save_payment_voucher`/`fn_save_receipt` derive header `total_amount`/`total_ewt`/`total_cwt` from the persisted lines (client header ignored); the ready validators reject any header cash total diverging from `SUM(line payment_amount)` before posting; header withholding totals now equal line sums exactly (closes the 0.02 export-blocking drift). Cash sales unaffected.

First fix (below) — ATC document-date validation and rate versioning, closing **PXL-AUD-035** and **PXL-AUD-036**.

Shipped (verified; committed `664f700` + pushed to origin branch; hosted push + merge-to-main pending):

- `supabase/migrations/20260713000002_atc_document_date_versioning.sql` — a trusted replacement for the held-out draft `20260710000004` (which stays untracked/excluded). AUD-035: the PV/OR/CV EWT-CWT validators take a trailing `p_document_date DATE` and evaluate the ATC effective window as of the document date; all callers thread `voucher_date`/`receipt_date`. AUD-036: version-aware uniqueness `(code, tax_category, effective_from)`, overlap/successor integrity guard, `fn_atc_version_asof` resolver, and effective_from immutability once used.
- `supabase/tests/033_atc_document_date_versioning_test.sql` — ATC-DOCDATE-VERSION-001, 15 assertions.
- Docs updated: findings (AUD-035/036 → Retested Passed + detail + changelog + standing 45/11/16), readiness (TAX-001/002 done), rules matrix, test book, state/handoff/queue.

Verification: held-out-safe reset replayed through `20260713000002`; full pgTAP **616/616 across 32 files**; build/lint green; types + schema summary regenerated; docs gate green (72 findings, 32 tests). The three broken drafts were restored byte-for-byte (checksums verified).

Exact next step: push `20260713000001` + `20260713000002` to hosted once a `SUPABASE_ACCESS_TOKEN` is present (move held-out `20260710000004`/`00005` aside during the push). Then advance **DA-009** (SAWT/QAP multi-ATC reconciliation, now unblocked by ATC versioning) or the EWT lane (AUD-041 remittance/application flow, then AUD-037 basis policy). Optional UI follow-up: resolve frontend ATC pickers through `fn_atc_version_asof` by document date.

## Prior Priority (session 76 — Accounting Rules Matrix under PXL Accounting Core Ready)

User directed that the Sales Invoice Workspace and Report Workspace standards are now documented, and that no new UI standards, report pilots, dashboards, or transaction workspace rollouts should be started. The next milestone is **PXL Accounting Core Ready**.

Completed in this documentation/architecture-alignment pass:

- Added `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md` as the active production-readiness control document.
- Added `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md` as the governed posting-behavior source of truth.
- Added DEC-017 in `AI/AI_DECISIONS.md`: PXL Accounting Core Ready supersedes DEC-015's temporary transaction-workspace-first ordering.
- Added DEC-018 in `AI/AI_DECISIONS.md`: PXL Accounting Rules Matrix is the governed posting source of truth.
- Added AIQ-017 in `AI/AI_WORK_QUEUE.md` as the active priority.
- Added AIQ-018 in `AI/AI_WORK_QUEUE.md` as completed architecture/docs work.
- Marked AIQ-015 P5B and report pilots as paused until the accounting core is ready.
- Updated related docs so future work starts from accounting/tax/master-data correctness, not UI expansion.

The active workstreams must be handled in order:

1. Accounting Engine.
2. Posting Engine.
3. Account Determination Engine.
4. Configuration-driven Tax Engine.
5. Master Data Governance.
6. CAS/BIR Readiness.
7. Transaction Rollout.
8. Report Rollout.
9. Dashboards.
10. Client Portal.
11. AI / Automation.

Do not:

- create new UI standards;
- implement report pilots;
- roll out transaction workspaces to additional document types;
- create dashboards;
- build new transaction pages unless required to fix accounting/tax/core-readiness defects.

Recommended next implementation lane:

1. Use `PXL_ACCOUNTING_RULES_MATRIX.md` as the accounting behavior reference before any implementation.
2. Reopen the core Criticals and dependencies: **PXL-DA-009** and **PXL-DA-019**.
3. Complete safe ATC document-date/version governance, replacing the held-out draft rather than adopting it as-is.
4. Build controlled EWT remittance / CWT application flow.
5. Decide and encode withholding basis policy.
6. Server-recompute OR/PV settlement totals from lines.
7. Add CM/VC-aware over-apply guards.
8. Complete financial statement/close readiness.
9. Complete semantic transaction events.
10. Define and implement the configuration-driven tax-rule model.
11. Complete governed master-data gaps required by posting/tax.

Held-out files remain excluded unless explicitly owned and fixed:

- `supabase/migrations/20260710000004_atc_document_date_versioning.sql`
- `supabase/migrations/20260710000005_cas_numbering_void_dat_controls.sql`
- `supabase/tests/027_cas_end_to_end_controls_test.sql`

## Previous Active Priority (session 74 — Official Report Workspace Standard)

User directed that before implementing or redesigning additional report pages, PXL must define the official report-page equivalent of the Sales Invoice Transaction Workspace Standard. Completed as a documentation and architecture-alignment pass only:

- Added `docs/PXL/PXL_STANDARD_REPORT_WORKSPACE.md` as the canonical reporting standard.
- Added DEC-016 in `AI/AI_DECISIONS.md`: the PXL Standard Report Workspace is the official UI, UX, data, reconciliation, drilldown, export, audit, provenance, security, performance, and rollout architecture for all PXL reports.
- The document covers:
  - core reporting philosophy and relationship to transaction workspaces;
  - standard report page structure;
  - report header, purpose, company/branch/period/currency context, filter bar, and report modes;
  - KPI/summary strip rules;
  - reconciliation states and server-side validation requirements;
  - enterprise report table behavior;
  - financial statement presentation;
  - drilldown and drillback rules;
  - report tabs/subsections, exceptions, warnings, exports, print, snapshots, audit/provenance, personalization, permissions, security, and performance;
  - report-specific documentation requirements;
  - reusable report component inventory;
  - developer guidelines for future shared report components/hooks/types;
  - current routed report rollout matrix covering Accounting, Sales/AR, Purchasing/AP, Banking, Inventory, Fixed Assets, Tax/Compliance, Books/CAS, Audit/System, and Management reports;
  - pilot-first implementation policy and success criteria.
- No report pages were rebuilt.
- No schema, API, business logic, posting, tax, reconciliation, or permission behavior was changed.
- No audit finding was created because this was architecture documentation and no genuine accounting/tax/security/data-integrity/report-correctness defect was confirmed.

After **PXL Accounting Core Ready**, future report work must use `docs/PXL/PXL_STANDARD_REPORT_WORKSPACE.md` first. Do not redesign isolated report pages. Select a pilot by production priority and dependency; recommended candidates are Trial Balance, AR Aging, and VAT Reconciliation.

## Previous Active Priority (session 73 — Official Transaction Workspace Standard)

User directed that before implementing any additional transaction workspaces, the Sales Invoice Workspace must be fully documented as the official PXL Transaction Workspace Standard. Completed as a documentation-only pass:

- Replaced `docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md` with the canonical standard document.
- The document now covers:
  - workspace philosophy and ERP rationale;
  - header standard, allowed/forbidden header data, toolbar actions, status chips, KPIs;
  - three-card information band standard and master-data link rules;
  - complete tab architecture for Lines, Financial, GL Impact, Tax Impact, Validation, Workflow, Approval, Audit, Related Docs, Related Party, Attachments, Activity, Notes, and System;
  - Lines/Smart Grid behavior, saved views, column chooser, pinned columns, totals, expandable rows, and cross-module reuse;
  - accounting/supporting tab standards;
  - UI/UX standards for spacing, borders, typography, color, tables, empty/loading states, responsiveness, and accessibility;
  - reusable component inventory and current file ownership;
  - future transaction extension rules;
  - developer guidelines for folder structure, React/TypeScript contracts, data loading, permissions, testing, and naming;
  - Sales Invoice reference implementation details;
  - UX decision log documenting removed duplicate right rail, Quick Actions card, duplicated header/card data, status strip, workflow header path, decorative color, and simple column chooser;
  - rollout matrix and maintenance rules.
- No code/schema/API/business behavior was changed.
- Verify with `git diff --check` before commit/push; docs-only build is not required unless additional code changes occur.

After **PXL Accounting Core Ready**, transaction implementation work must use `docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md` as the governing reference before building Purchase Invoice/Vendor Bill, Sales Order, Purchase Order, Delivery Receipt, Official Receipt, Credit Memo, Debit Memo, Journal Entry, Inventory Transactions, etc.

## Previous Active Priority (session 72 — Saved Views / Professional Table Experience)

User requested the next table-only enhancement after declaring the Transaction Workspace visually complete. Implemented as a reusable `LineGrid` enhancement, not a page redesign and with no schema/API/posting/business changes:

- `LineGrid` is now a reusable enterprise transaction table framework with:
  - Built-in view selector support and system/custom views.
  - Browser-local persisted preferences scoped by caller `storageKey`: selected view, saved custom views, visible columns, column order, pinned columns, column widths, density, sorting, and global filter.
  - Custom view management: Save View, Update View / Save as Custom, Rename, Delete, Restore Current View, Restore System Default.
  - Professional Choose Columns panel: search, Select All, Clear All, reset actions, column groups (General/Sales/Inventory/Tax/Accounting/Dimensions/Audit/System), visible-column drag-and-drop ordering, and pin/unpin controls.
  - Manual column resizing, sticky headers, sticky totals row where present, sticky pinned identity columns, compact/comfortable/spacious density, global filter, CSV export, and refresh hook.
- `SalesInvoiceDocumentPage` wires the Sales Invoice line table to the new system:
  - System views: **Default, Accounting, Tax, Audit, Inventory, Sales**, plus built-in **Custom** from `LineGrid`.
  - Default pinned columns: `#`, `Item Code`, `Description`.
  - Column metadata now supplies grouping, default widths, sort/filter/export values, and truthful unavailable states for not-yet-stored fields.
  - Refresh button reuses the existing invoice `load()` function.
- Docs updated: `PXL_STANDARD_TRANSACTION_WORKSPACE.md`, `PXL_TRANSACTION_EXPERIENCE_STANDARD.md`, and `PXL_TRANSACTION_MATRIX.md` now record the saved-view table standard.
- Verification: `npm run build` passes; `npm run lint` passes; `git diff --check` clean. The user-owned held-out `20260710000004`, `20260710000005`, and test `027` were not touched.

Known boundary: persistence is browser-local (`localStorage`) and scoped by workspace/table key (including company for SI), not a database-backed cross-device user preference table. That matches the user's "no schema/API changes" constraint for this UI-only pass; if cross-device per-auth-user preferences become required, add a governed preference table/API as a separate explicit feature.

## Previous Active Priority (session 71 — Sales Invoice workspace final UI polish)

User declared the workspace functionally complete and requested UI/UX refinement only. Implemented on top of the pushed session-69 baseline (uncommitted):

- `DocumentLayout`: reduced header height again, moved Posting / Collection / Lock into compact header chips, removed the separate horizontal status/workflow strip, kept only state color dots, and gave the tab strip a subtle company-accent tint with the active tab using the stronger accent.
- `DocumentToolbar`: More now renders via `createPortal(document.body)` with fixed positioning, `z-[9999]`, auto flip up/down, viewport-aware left/right alignment, outside-click/Escape close, and a high-elevation shadow. Toolbar auto-limits visible primary actions to at most three buttons plus More.
- `PrimaryInformationPanel`: now adapts to three compact cards and uses tighter card padding/gaps.
- `SalesInvoiceDocumentPage`: removed the entire Quick Actions card. Header toolbar is now the single action source (Create Receipt/Post/Submit as primary by state, Print, Email, More). Workflow moved from the permanent header into a dedicated Workflow tab. Draft Edit moved under More.
- Final visual pass: added shared ERP presentation primitives (`ErpSectionHeader`, compact empty state, table class constants) and standardized tab section headers, table row/header sizing, numeric alignment, total rows, empty states, sharper 2-4px radii, lighter borders/shadows, and calmer neutral row highlights across Lines, Financial, GL Impact, Tax Impact, Validation, Workflow, Approval, Audit, Related Docs, Related Party, Attachments, Activity, Notes, and System.
- `GLImpactPanel`: removed decorative action icons, compacted header/context rows, converted balanced/out-of-balance to a small state badge, standardized the accounting table, and kept existing links/actions unchanged.
- `AuditTrailSection` and transaction support cards: compacted internal spacing/table rhythm and sharpened corners to match the workspace.
- More-menu/deep-link polish retained: lower-frequency actions live under More (Credit/Debit Memo, Open Customer, Open Journal Entry, View Ledger, View Tax Ledger, Generate E-Invoice); `/customers?customerId=...`, `/ar-aging?tab=ledger&customerId=...`, and `/sales-tax-review?sourceId=...` remain wired.
- No business features were added; this was UI density, hierarchy, color, and duplication cleanup only.
- Verification: `npm run build` passes; `npm run lint` passes; `git diff --check` clean; port 5173 had returned 200 earlier in the session. The user-owned held-out `20260710000004`, `20260710000005`, and test `027` were not touched.

Session 69 baseline already included:

- `PrimaryInformationPanel`: compact cards — Document Information, Customer Information, Sales Context. Document card keeps only Invoice Date, Due Date, Branch, Currency, Payment Terms, and Reference when present. Customer card keeps only clickable Customer, Customer Code, TIN, and VAT Classification. Sales Context keeps only Salesperson, Project, Cost Center, Department.
- Moved duplicate fields to the correct homes: Source Type + Document Series to System; Official Receipt links to Related Documents; Created/Last Modified By to Audit; full Customer Master / credit / contact / address / payment / sales / aging data to the new Related Party tab.
- `Related Party` tab added: identity, contacts, addresses, tax profile, credit profile, payment information, sales information, AR aging summary via `fn_ar_aging_asof`, recent invoices, and recent payments.
- `TransactionTabsBar`: equal-width one-line tabs including Related Party, no arrows/horizontal scrollbar; labels shrink/truncate safely.
- `LineGrid`: Operations/Accounting/Audit/All profiles, individual column chooser, 25-column SI pool, inline expandable line detail, and Lines/Quantity/Net/VAT/EWT/Gross/Discount/Grand Total band. SI row detail exposes recognition, serial/lot/allocation, dimensions, tax, audit, source, posting rule, related docs, and item notes with truthful unavailable states.
- SI tabs: full Financial contract including explicit untracked values; expanded GL table; expanded tax-ledger table (VAT-only correctness boundary retained); explicit validation checklist; multi-row approval table; chronological audit evidence with IP/device/change fields; attachment table empty state; four note categories; expanded System metadata.
- Master-data governance: migration `20260713000001_company_workspace_appearance.sql` adds checked `companies.workspace_accent_color`; Company Setup maintains/previews it; generated database types updated. App content width is 1600px and dynamic transaction breadcrumbs resolve to the register + workspace.
- Verification: `npm run build` passes; `npm run lint` passes; `git diff --check` clean. Vite remains available on port 5173. The user-owned held-out `20260710000004`, `20260710000005`, and test `027` were not touched.

**Historical remaining UI work — paused by DEC-017:** (1) relocate draft create/edit + `/sales-invoices/new` into this same routed shell and retire the register form; (2) expand the register actions/columns; (3) create and link the missing governed master-data entities/FKs/UI (Salesperson, Price Level, Territory, Industry, Project, Delivery Terms, Campaign, Opportunity, SI header/line dimensions); (4) attachment/OCR, semantic activity, categorized note storage, document hash/version fields, and e-invoice integration. These remain valid future tasks, but they must wait until **PXL Accounting Core Ready**.

## Historical Priority (session 67 — SI complete reference workspace; superseded by DEC-017)

Sales Invoice is now the **complete reference implementation** of the Standard Transaction Workspace (build + lint 0 warnings green; HMR verified; **uncommitted**). Added this session on `SalesInvoiceDocumentPage.tsx` + new shared components:

- **`PrimaryInformationPanel`** (new) — Document / Customer / Sales-Context groups, auto-populated read-only with provenance hints (§5/§6). Fetches Customer master, branch, payment terms.
- **Header statuses**: Posting / Collection / Lock badges + full workflow strip (Draft→Approved→Posted→Partially Paid→Paid; Voided). Collection derived from posted `receipt_lines`.
- **12 tabs**: Lines (+ new **`LineDetailPanel`** on row-select via new `LineGrid` `onRowClick`/`selectedKey`) · Financial Summary (full contract incl. collection) · GL Impact · Tax Impact · Posting Validation · **Approval** (`approval_instances` or empty state) · Audit Trail · Related Documents · **Attachments** (deferred empty state) · **Activity Timeline** (lifecycle facts) · **Notes** (memo) · System.
- **Full right sidebar** via new **`SidebarCard`**/`CardRow`: Financial Summary · Customer Snapshot (credit limit, available credit) · Tax Summary · Posting Validation · Quick Actions · Audit Summary.
- **`DocumentLayout`** gained a `primary` slot (renders Primary Information above tabs).
- Docs: workspace-doc pilot section rewritten; Master Data gaps (Salesperson/Price List/dimensions) logged in the backlog (enhancement, not a finding).

**Historical next step — paused by DEC-017:** draft/edit relocation, register expansion, column profiles, and visual polish remain future transaction-workspace tasks, but the active priority is now accounting-core hardening.

## Historical Priority (session 66 — SI canonical pilot refinement; superseded by DEC-017)

User directive: make the **Sales Invoice** the canonical/reference implementation of the Standard Transaction Workspace, and consolidate the duplicate viewing experience into ONE routed workspace. Shipped this session (build + lint 0 warnings green, HMR verified; committed pending):

- **Viewing consolidated**: `SalesInvoicePage` register now routes non-draft rows to the canonical `/sales-invoices/:id` workspace (`openDocument`); drafts still open the register editor. The modal read-only view path is no longer reached from the list.
- **Lifecycle actions on the route**: `SalesInvoiceDocumentPage` toolbar does Submit-for-Approval / Post / Return-to-Draft / Void (reason dialog) via `fn_approve/post/revert/void_sales_invoice`; server enforces role/SoD; actions shown only for the states that allow them; posted = never editable.
- **Reusable `RelatedDocumentsTab`** (`src/components/document/RelatedDocumentsTab.tsx`): renders the full chain, existing links clickable (JE via `journal_entries.reference_doc_type='SI'`; receipts via `receipt_lines.invoice_id`), missing stages show None + create action. Wired into the SI Related Documents tab.
- **System tab** added; docs updated (`PXL_STANDARD_TRANSACTION_WORKSPACE.md`: pilot section + RelatedDocuments contract + rollout matrix).

**Historical exact next step — paused by DEC-017:** route consolidation, tab expansion, register expansion, right-sidebar/card work, visual pass, and Vendor Bill rollout remain future transaction-workspace tasks. Do not resume them until **PXL Accounting Core Ready**.

## Historical Priority (session 65 — superseded by DEC-017)

**Historical note:** AIQ-015 was the active sole priority under DEC-015. DEC-017 supersedes that ordering. The two remaining Criticals (**PXL-DA-009**, **PXL-DA-019**) are no longer intentionally paused by workspace work; they are part of the active accounting-core lane.

Work the AIQ-015 phase plan (`AI/AI_WORK_QUEUE.md`) in order; the in-session task list mirrors it. Done this session (65): Phase 0 governance (DEC-015 + queue + issue-routing + state/handoff); **Phase 1 Shell** — `src/components/document/DocumentLayout.tsx` exports `DocumentLayout`, `WorkflowStrip`, `TransactionTabs`, `DocumentToolbar` (fixed order + More ▾), reusing `StatusBadge`; **Phase 2 routes** — `/sales-invoices/:id` deep-link route in `src/App.tsx`; list rows link via "Open ↗" (`src/pages/SalesInvoicePage.tsx`); **Phase 3 SI view** — `src/pages/SalesInvoiceDocumentPage.tsx` renders a read-only document-of-record through `DocumentLayout` with tabs Lines · GL Impact (`GLImpactPanel`, real posted JE) · Posting Validation (derived checklist) · Audit Trail (`AuditTrailSection`, PXL-AUD-050 now visible) · Related, plus a right-rail Financial Summary (§8 SI contract) + Party card and a workflow strip. `npm run build` + `npm run lint` green; Vite dev server HMR-verified. The existing list+modal for create/edit is untouched (adopt-on-touch).

Phase 4 also shipped this session: `src/components/document/FinancialSummaryPanel.tsx` (generic group-based §8 panel) and `PostingValidationPanel.tsx` (with `readinessToChecks`, which bridges the live `useTransactionReadiness` server preflight into the §11 checklist); the SI document page consumes both (right-rail summary + live preflight for draft/approved, derived checks for posted/voided). build + lint (0 warnings) green, HMR verified.

Phase 5 also shipped this session (user-approved VAT-only scope): `src/components/document/LineGrid.tsx` (column-group-aware, read-only, totals footer, structured for later editing) — the SI Lines tab uses it with a Revenue-Acct provenance column (§5); and `TaxImpactPanel.tsx` (reads `tax_detail_entries`, **VAT kinds only**, draft fallback) added as the Tax Impact tab. EWT/CWT rows and the full §7 account-determination ladder + editable line entry are deferred (the withholding base needs PXL-AUD-031/032/033; editing needs the route-driven create/edit form). build + lint (0 warnings) green, HMR verified.

**Historical exact next step — paused by DEC-017:** Phase 6 rollout to the core four, secondary docs, RelatedDocumentsTab, and config layer must wait until **PXL Accounting Core Ready**.

## Work In Progress (session 64, shipped)

The first PXL-DA-019 CAS/BIR slice is complete, verified, committed (`ffe7782`, pushed to `origin/main`), and pushed to hosted (`20260712000003`/`20260712000004` applied to `bskjkogijpbhukjkagfj`; held-out `20260710000004`/`00005` moved aside during the push and remain off hosted; local = remote through `20260712000004`). Delivered this session:

- `20260712000003_posting_runtime_repairs.sql` / test 031 (49 assertions): repaired the three schema-lint-surfaced deployed defects — source-warehouse branch for stock-transfer JE numbering (JE stays branch-unattributed); physical-count value kept derived on the immutable line/inventory transaction (no `variance_cost` column); explicit optional `vendor_bills.rr_id` FK validated by `fn_save_vendor_bill` (received + same company/supplier) and consumed by purchase-return completion.
- `20260712000004_cas_numbering_void_evidence.sql` / test 032 (25 assertions): immutable issuance/void evidence on the preserved three-argument branch-scoped allocator (no two-argument overload, no one-unresolved-reservation rule), `number_series` guard, atomic ATP exhaustion without counter drift, allocation/void triggers, an owner-proof `P0001` immutability trigger on void evidence, historical backfill, and `vw_cas_atp_usage`. Two initially-failing test-032 assertions were fixed in the migration during this session: void evidence now snapshots the pre-void `OLD` row (status `posted`), and a `BEFORE UPDATE/DELETE/TRUNCATE` trigger makes void evidence immutable even to the table owner.
- `VendorBillsPage` captures the optional receiving report; CAS Void Register / ATP Usage / Dashboard / Audit Report pages read the governed objects. README PostgreSQL-version/migration wording and disabled opt-in demo seeding were corrected. DEC-014 records the database-governed numbering/void-evidence decision.

## Recovery / Exact Next Step

Session 64 is fully shipped (verified + committed + Git + hosted). Continue DA-019 or DA-009:

1. DA-019 remaining slices: true BIR DAT record layout (record-type/fixed-width formats), immutable books reconciliation, and exported-byte (not just frozen-row) export provenance. Build on the governed numbering/void evidence now in place.
2. Or DA-009 dependencies: safe ATC date/version, PXL-AUD-041 remittance flow.
3. Standing hold: the user-owned broken drafts `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` remain untracked and must keep being moved aside byte-for-byte during any reset / full pgTAP / `supabase db push --linked` / docs-gate run until explicitly owned and fixed (2026-07-11 decision). `supabase db push --linked` needs them aside because their `20260710` timestamps sort before the last remote migration and would otherwise require `--include-all`.

## Known Remaining DA-019 Boundary

The current CAS export RPC hashes frozen JSON rows, but the browser still serializes the downloaded CSV bytes. Exact exported-byte hashing and verified BIR DAT layout remain a later DA-019 slice; do not mark the full Critical finding closed after numbering/void evidence alone.
