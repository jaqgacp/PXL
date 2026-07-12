# AI Handoff

Last updated: 2026-07-12 (session 65 — priority pivot to the Standard Transaction Workspace, DEC-015)

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
