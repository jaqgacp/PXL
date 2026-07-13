# AI Handoff

Last updated: 2026-07-13 (session 69 — compact-header Sales Invoice refinement)

## Active Priority (session 69 — compact Sales Invoice master-template UI)

User refined the Sales Invoice workspace standard: reduce header height, remove duplicated master/audit/system/related fields from the permanent header/cards, and move the full customer/vendor profile into a new Related Party tab. Implemented on top of the session-68 dense-view baseline (uncommitted):

- `DocumentLayout`: shorter company-accent document header with clickable customer name (TIN removed from the colored header), Invoice Total/Collected/Balance Due, inverted status-aware toolbar, tighter one-line Posting/Collection/Lock + workflow strip, 3% accent-derived workspace tint, no right rail, compact footer metadata.
- `PrimaryInformationPanel`: exactly four independent compact cards — Document Information, Customer Information, Sales Context, Quick Actions. Document card now keeps only Invoice Date, Due Date, Branch, Currency, Payment Terms, and Reference when present. Customer card keeps only clickable Customer, Customer Code, TIN, and VAT Classification. Sales Context keeps only Salesperson, Project, Cost Center, Department. Quick Actions keeps only Create Receipt, Create Credit Memo, Print, Email, and Open Full Accounting Trace.
- Moved duplicate fields to the correct homes: Source Type + Document Series to System; Official Receipt links to Related Documents; Created/Last Modified By to Audit; full Customer Master / credit / contact / address / payment / sales / aging data to the new Related Party tab.
- `Related Party` tab added: identity, contacts, addresses, tax profile, credit profile, payment information, sales information, AR aging summary via `fn_ar_aging_asof`, recent invoices, and recent payments.
- More-menu/deep-link polish: lower-frequency actions moved to More (Debit Memo, Open Customer, Open Journal Entry, View Ledger, View Tax Ledger, Generate E-Invoice); `/customers?customerId=...` opens the Customer master view; `/ar-aging?tab=ledger&customerId=...` preselects the ledger customer; `/sales-tax-review?sourceId=...` filters to the invoice.
- `TransactionTabsBar`: equal-width one-line tabs including Related Party, no arrows/horizontal scrollbar; labels shrink/truncate safely.
- `LineGrid`: Operations/Accounting/Audit/All profiles, individual column chooser, 25-column SI pool, inline expandable line detail, and Lines/Quantity/Net/VAT/EWT/Gross/Discount/Grand Total band. SI row detail exposes recognition, serial/lot/allocation, dimensions, tax, audit, source, posting rule, related docs, and item notes with truthful unavailable states.
- SI tabs: full Financial contract including explicit untracked values; expanded GL table; expanded tax-ledger table (VAT-only correctness boundary retained); explicit validation checklist; multi-row approval table; chronological audit evidence with IP/device/change fields; attachment table empty state; four note categories; expanded System metadata.
- Master-data governance: migration `20260713000001_company_workspace_appearance.sql` adds checked `companies.workspace_accent_color`; Company Setup maintains/previews it; generated database types updated. App content width is 1600px and dynamic transaction breadcrumbs resolve to the register + workspace.
- Verification: `npm run build` passes; `npm run lint` passes; `git diff --check` clean. Vite remains available on port 5173. The user-owned held-out `20260710000004`, `20260710000005`, and test `027` were not touched.

**Remaining before declaring the entire final brief complete:** (1) relocate draft create/edit + `/sales-invoices/new` into this same routed shell and retire the register form; (2) expand the register actions/columns; (3) create and link the missing governed master-data entities/FKs/UI (Salesperson, Price Level, Territory, Industry, Project, Delivery Terms, Campaign, Opportunity, SI header/line dimensions); (4) attachment/OCR, semantic activity, categorized note storage, document hash/version fields, and e-invoice integration. Do these as schema-backed capabilities, never static selectors. Then use this workspace as the base for Vendor Bill and every other transaction.

## Active Priority (session 67 — SI complete reference workspace)

Sales Invoice is now the **complete reference implementation** of the Standard Transaction Workspace (build + lint 0 warnings green; HMR verified; **uncommitted**). Added this session on `SalesInvoiceDocumentPage.tsx` + new shared components:

- **`PrimaryInformationPanel`** (new) — Document / Customer / Sales-Context groups, auto-populated read-only with provenance hints (§5/§6). Fetches Customer master, branch, payment terms.
- **Header statuses**: Posting / Collection / Lock badges + full workflow strip (Draft→Approved→Posted→Partially Paid→Paid; Voided). Collection derived from posted `receipt_lines`.
- **12 tabs**: Lines (+ new **`LineDetailPanel`** on row-select via new `LineGrid` `onRowClick`/`selectedKey`) · Financial Summary (full contract incl. collection) · GL Impact · Tax Impact · Posting Validation · **Approval** (`approval_instances` or empty state) · Audit Trail · Related Documents · **Attachments** (deferred empty state) · **Activity Timeline** (lifecycle facts) · **Notes** (memo) · System.
- **Full right sidebar** via new **`SidebarCard`**/`CardRow`: Financial Summary · Customer Snapshot (credit limit, available credit) · Tax Summary · Posting Validation · Quick Actions · Audit Summary.
- **`DocumentLayout`** gained a `primary` slot (renders Primary Information above tabs).
- Docs: workspace-doc pilot section rewritten; Master Data gaps (Salesperson/Price List/dimensions) logged in the backlog (enhancement, not a finding).

**Remaining for a fully-complete pilot (next):** (1) **draft create/edit FORM relocation** onto the route to fully retire the register modal (biggest remaining; touches `fn_save_sales_invoice` + line editing — verify posting unchanged) — task 7; (2) **register list** column expansion + status-aware Actions menu — task 10; (3) accountant/auditor **line-grid column profiles** + column chooser; (4) visual/density polish + PXL_TRANSACTION_MATRIX SI-workspace note — task 12. Then roll to **Vendor Bill**. Verify each with `npm run build` / `npm run lint`. Issue-routing (DEC-015): defects → audit findings in severity order; enhancements → backlog/vision.

## Active Priority (session 66 — SI canonical pilot refinement)

User directive: make the **Sales Invoice** the canonical/reference implementation of the Standard Transaction Workspace, and consolidate the duplicate viewing experience into ONE routed workspace. Shipped this session (build + lint 0 warnings green, HMR verified; committed pending):

- **Viewing consolidated**: `SalesInvoicePage` register now routes non-draft rows to the canonical `/sales-invoices/:id` workspace (`openDocument`); drafts still open the register editor. The modal read-only view path is no longer reached from the list.
- **Lifecycle actions on the route**: `SalesInvoiceDocumentPage` toolbar does Submit-for-Approval / Post / Return-to-Draft / Void (reason dialog) via `fn_approve/post/revert/void_sales_invoice`; server enforces role/SoD; actions shown only for the states that allow them; posted = never editable.
- **Reusable `RelatedDocumentsTab`** (`src/components/document/RelatedDocumentsTab.tsx`): renders the full chain, existing links clickable (JE via `journal_entries.reference_doc_type='SI'`; receipts via `receipt_lines.invoice_id`), missing stages show None + create action. Wired into the SI Related Documents tab.
- **System tab** added; docs updated (`PXL_STANDARD_TRANSACTION_WORKSPACE.md`: pilot section + RelatedDocuments contract + rollout matrix).

**Exact next step (remaining for a complete pilot):** (1) relocate the draft create/edit FORM onto the canonical route so the modal is fully retired (final consolidation — biggest remaining piece; touches `fn_save_sales_invoice` + line editing; verify posting unchanged); (2) upgrade GL Impact / Tax Impact / Approval tabs to full spec tables + add Line Detail Panel + Attachments/Activity Timeline/Notes tabs (task 9); (3) register column expansion + status-aware Actions menu (task 10); (4) expand right-sidebar cards + Customer Snapshot from master data, logging Master Data gaps (task 11); (5) visual/density pass + finish docs/rollout (task 12). Then roll to Vendor Bill. Verify each with `npm run build` / `npm run lint`. Issue-routing (DEC-015): defects → audit findings in severity order; enhancements → vision/backlog.

## Active Priority (session 65)

**AIQ-015 — Standard Transaction Workspace is the active sole priority (DEC-015).** The two remaining Criticals (**PXL-DA-009**, **PXL-DA-019**) are **paused** — still Open, not withdrawn, revisited only after the scheduled workspace phases or on user direction. Do not resume them without the user.

Work the AIQ-015 phase plan (`AI/AI_WORK_QUEUE.md`) in order; the in-session task list mirrors it. Done this session (65): Phase 0 governance (DEC-015 + queue + issue-routing + state/handoff); **Phase 1 Shell** — `src/components/document/DocumentLayout.tsx` exports `DocumentLayout`, `WorkflowStrip`, `TransactionTabs`, `DocumentToolbar` (fixed order + More ▾), reusing `StatusBadge`; **Phase 2 routes** — `/sales-invoices/:id` deep-link route in `src/App.tsx`; list rows link via "Open ↗" (`src/pages/SalesInvoicePage.tsx`); **Phase 3 SI view** — `src/pages/SalesInvoiceDocumentPage.tsx` renders a read-only document-of-record through `DocumentLayout` with tabs Lines · GL Impact (`GLImpactPanel`, real posted JE) · Posting Validation (derived checklist) · Audit Trail (`AuditTrailSection`, PXL-AUD-050 now visible) · Related, plus a right-rail Financial Summary (§8 SI contract) + Party card and a workflow strip. `npm run build` + `npm run lint` green; Vite dev server HMR-verified. The existing list+modal for create/edit is untouched (adopt-on-touch).

Phase 4 also shipped this session: `src/components/document/FinancialSummaryPanel.tsx` (generic group-based §8 panel) and `PostingValidationPanel.tsx` (with `readinessToChecks`, which bridges the live `useTransactionReadiness` server preflight into the §11 checklist); the SI document page consumes both (right-rail summary + live preflight for draft/approved, derived checks for posted/voided). build + lint (0 warnings) green, HMR verified.

Phase 5 also shipped this session (user-approved VAT-only scope): `src/components/document/LineGrid.tsx` (column-group-aware, read-only, totals footer, structured for later editing) — the SI Lines tab uses it with a Revenue-Acct provenance column (§5); and `TaxImpactPanel.tsx` (reads `tax_detail_entries`, **VAT kinds only**, draft fallback) added as the Tax Impact tab. EWT/CWT rows and the full §7 account-determination ladder + editable line entry are deferred (the withholding base needs PXL-AUD-031/032/033; editing needs the route-driven create/edit form). build + lint (0 warnings) green, HMR verified.

**Exact next step: Phase 6** — roll `DocumentLayout` across the core four (Official Receipt, Vendor Bill, Payment Voucher) adopt-on-touch, reusing the now-built shared components (`DocumentLayout`, `FinancialSummaryPanel`, `PostingValidationPanel`, `LineGrid`, `TaxImpactPanel`, `WorkflowStrip`); each needs its own §8 summary contract + §5 columns + document-code/config for the readiness hook. Then secondary docs, the `RelatedDocumentsTab` (§12, reads existing links), and the config layer (§14). Still-open deferred sub-items: route-driven `/sales-invoices/new` + `/:id/edit`; editable `LineGrid` mode; role-gated accounting columns. Verify each with `npm run build` / `npm run lint`. Issue-routing (DEC-015): defects → `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` in severity order; enhancements → vision/backlog.

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
