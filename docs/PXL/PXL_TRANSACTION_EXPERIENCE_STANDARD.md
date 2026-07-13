# PXL Transaction Experience Standard

Status: DESIGN BLUEPRINT subordinate to `PXL_STANDARD_TRANSACTION_WORKSPACE.md` (the official product vision, user directive 2026-07-10, DEC-013). This file carries the implementation-level detail (tab specs, line-grid column groups, auto-population matrix, account-determination ladder, panel contracts, maturity table); when the two disagree, the vision document wins and this file must be updated. Nothing here is implemented by this document, and no page is required to change until its Phase 2 session is scheduled. Audit-finding work always outranks this standard (DEC-012).

Active sequencing gate: `PXL_ACCOUNTING_CORE_READINESS.md` (DEC-017). Transaction-experience rollout is paused until **PXL Accounting Core Ready** is cleared. Use this file as a reference only during the core-readiness phase.

## 1. Purpose and Normative Status

Every accounting document in PXL must eventually expose enough accounting, tax, audit, workflow, and operational information to satisfy a BIR auditor — while remaining capturable by a non-accountant. This document defines that target: the standard layout, tab set, line grid, auto-population rules, account determination, summary panels, and drill contracts that every future transaction page follows. New pages adopt it from day one; existing pages converge when they are next touched ("adopt-on-touch"), never as a mass refactor.

Precedence when documents disagree:

1. `PXL_ACCOUNTING_RULES_MATRIX.md` — governed posting behavior, account determination, tax impact, reversal/void/cancel, and test expectations.
2. `PXL_TRANSACTION_MATRIX.md` + migrations — transaction lifecycle/source behavior.
3. This standard — what transaction pages should LOOK like and expose.
4. `UI_UX_PRINCIPLES.md` — visual/interaction language. Note: its implementation notes name a stack (Zustand stores, react-hook-form + Zod "exclusively", shadcn Tabs) that is installed but deliberately NOT adopted (see `PXL_ARCHITECTURE_SUMMARY.md` and the backlog's Frontend Architecture section, session 42). Those notes are aspirational; the selective-adoption policy in `PXL_PRODUCT_BACKLOG.md` governs. Do not mass-migrate forms to satisfy the principles doc.
5. `PXL_PRODUCT_BACKLOG.md` — holds the individual enhancement entries; its "Target: Standard Transaction Experience" section is superseded by (and now points to) this document.

## 2. Historical Baseline (verified 2026-07-04, session 48)

This section records the pre-workspace baseline and is not the current Sales Invoice state. As of 2026-07-13, Sales Invoice is the dense routed reference implementation described by `PXL_STANDARD_TRANSACTION_WORKSPACE.md`; draft/new route consolidation remains pending.

Pattern in production today: every transaction is a **list page + full-screen modal overlay** (`fixed inset-0`) for create/edit/view. There are no per-document routes — a document cannot be deep-linked, bookmarked, or opened from an emailed URL (UI Principle 38 unmet). No page has tabs. The only per-document panels that exist are:

| Capability | SI | OR | VB | PV | JE | CM | DM | VC | Cash Sale | Cash Purchase | CV |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Posting validation (SetupReadinessBanner) | ✓ | ✓ | ✓ | ✓ | — | — | — | — | — | — | — |
| GL Impact (preview + posted JE) | ✓ | ✓ | ✓ | ✓ | n/a (is the JE) | — | — | — | — | — | — |
| Financial summary section | ✓ | partial | ✓ | partial | balance row | partial | partial | — | ✓ | partial | partial |
| Tax impact panel | — | — | — | — | — | — | — | — | — | — | — |
| Audit info displayed (created/approved/posted by-at) | — | — | — | — | — | — | — | — | — | — | — |
| Related documents view | — | applied SIs in grid | — | applied VBs in grid | — | invoice link field | — | apply modal | — | — | — |
| Attachments / notes tab / timeline / workflow view | — | — | — | — | — | — | — | — | — | — | — |

Shared component inventory: `GLImpactPanel`, `SetupReadinessBanner`, `VATReconciliationPanel` are real and adopted on the core four. `src/components/ui/shared.tsx` already contains `StatusBadge` (adopted, 54 pages), plus `DataTable`, `LookupDialog`, `FormSection`, `AuditTrailSection`, `ConfirmDialog`, `EmptyState` — **all built and adopted by zero pages**; every transaction page hand-rolls its own table, form sections, confirm dialogs, and lookups (native `<select>`, no lookup windows, no inline master-data creation). The audit-trail data layer (`sys_audit_logs`, created/approved/posted stamps, void reasons) is complete server-side and invisible in every document UI (finding PXL-AUD-050).

Maturity against this standard (structure/exposure, not accounting correctness — that is scored in the findings doc):

- **Core four (SI, OR, VB, PV): ~60%** — validation + GL preview + summary exist; no tabs, no tax impact, no audit display, no related-documents navigation, no per-document routes.
- **Journal Entry: ~40%** — solid posting/reversal mechanics and balance indicator; no readiness preflight, no dimension columns in the UI (DB supports them per PXL-DA-017), no audit display, account picker is a bare `<select>` over the whole COA.
- **Secondary documents (CM, DM, VC, Cash Sale, Cash Purchase, CV): ~30%** — capture works; no validation banner, no GL impact, no tax impact, minimal summaries (PXL-AUD-049 covers the GL-panel slice).
- **Overall transaction experience: ~45%.**

## 3. The Standard Transaction Layout

Target anatomy for every transactional document (extends UI Principle 39):

**Final 2026-07-13 override:** one routed workspace per transaction (no separate View/Open page); compact company-accent header with document number, Posting/Collection/Lock chips, clickable party name, three primary metrics, and the only visible document actions; exactly three compact cards (Document, Party, Context); compact one-line tabs including Workflow and Related Party; active tab content; footer metadata. There is no right rail and no Quick Actions card. The older diagram below is retained only as design history where it conflicts with this override.

```
Route model:  /module/docs            list (DataTable + filters + toolbar)
              /module/docs/new        create
              /module/docs/:id        view (default for non-draft)
              /module/docs/:id/edit   edit (draft only)
              One Document component, parameterized by mode (Principle 38).

┌─ DOCUMENT HEADER BAR ────────────────────────────────────────────────┐
│ DOC-NO  [StatusBadge]  [workflow strip: Draft→Approved→Posted]       │
│ [Action toolbar — fixed order: Edit · Approve · Post · Print · More▾]│
├─ TRANSACTION INFORMATION (FormSection grid) ─────────────────────────┤
│ Date · Branch · Counterparty (lookup) · TIN · Terms · Currency · Ref │
│ Auto-populated master data is read-only with a provenance hint.      │
├─ LINE GRID (section 5) ──────────────────────────────────────────────┤
│ …with per-grid totals row                                            │
├─ SMART SUMMARY PANEL (right rail on wide screens; section 8) ────────┤
├─ POSTING VALIDATION (SetupReadinessBanner, always; section 11) ──────┤
├─ TABS (section 4) ───────────────────────────────────────────────────┤
│ GL Impact · Tax Impact · Related · Audit Trail · Attachments · Notes │
└──────────────────────────────────────────────────────────────────────┘
```

Rules:

1. **Every posting document gets the same anatomy.** Applicability varies by tab/column, never by inventing a different shape.
2. **View mode is the document of record**: posted documents open read-only with the posted JE, tax rows, and audit facts visible without extra clicks.
3. **The modal-overlay pattern is deprecated** for documents (retained for small masters and confirmations). Documents get routes so auditors, approvers, and support can link to them.
4. **Toolbar order is fixed** (UI Principle 16); inapplicable actions are disabled, not hidden; destructive actions live under More ▾ with reason capture (void reason codes already exist).
5. **No right rail, no Quick Actions card, and no duplicate header payload.** The three-card band is intentionally short. Actions belong only in the header toolbar; full counterparty insight belongs in the Related Party tab; workflow belongs in Workflow/Approval; financial, validation, audit, related-document, GL, tax, and system details belong in their dedicated tabs. Do not duplicate them in sidebar cards or oversized header cards.
6. **Enterprise polish is standardized, not page-specific.** Every tab starts with a compact section header; tables share one rhythm for headers, rows, numeric alignment, totals, hover states, and empty states; corners stay sharp, borders neutral, shadows light, and color is used only for state or interaction.

## 4. Standard Tab Set

| Tab | Content | Applies to | Notes |
| --- | --- | --- | --- |
| Lines | The line grid (section 5) | All | Primary tab; for OR/PV this is the application grid (invoices/bills applied). |
| Financial Summary | Per-type totals (section 8) | All | Dedicated tab; the header contains only the three primary metrics and does not replace the accounting breakdown. |
| GL Impact | Draft preview + posted JE + drill (section 9) | All posting docs | JE page itself omits it (the document IS the JE); non-posting docs (quotation, SO) show "No GL impact until …" explainer instead of hiding the tab. |
| Tax Impact | VAT/EWT/ATC/2307/SAWT/QAP linkage (section 10) | SI, OR, VB, PV, CM, DM, VC, Cash Sale, Cash Purchase, CV | Hidden for JE (manual JEs post no tax rows by design — matrix), fund transfers, and inventory docs; shown-empty with explainer for tax-registered docs with zero tax. |
| Posting Validation | Readiness checklist (section 11) | All posting docs | Always visible near the Post action, not only as a tab. |
| Approval | Configured workflow, approver, SoD state, approve/reject with reason | Docs with approval flows (SI, VB via approve RPCs; others as workflows are configured) | Backed by DEC-009/DEC-010 (`fn_can_perform`, SoD). Until multi-step routing exists, shows the single approve step + who did it. |
| Audit Trail | Created/updated/approved/posted/voided by+at, void reason, lock status, then `sys_audit_logs` entries (AuditTrailSection) | All | Data complete server-side today; finding PXL-AUD-050. |
| Activity Timeline | Semantic lifecycle story (created → approved → posted → …) | All | Depends on PXL-DA-016 `transaction_events`; until then the Audit Trail tab serves both purposes. Do NOT build two tabs before DA-016 lands — merge. |
| Related Documents | Document chain, both directions (section 12) | All | Includes JE ↔ source doc links, application links (OR↔SI, PV↔VB, VC↔VB, CM↔SI), certificates (PV→2307), returns/exports containing this doc. |
| Related Party | Embedded customer/vendor profile for the transaction | Sales and purchasing docs | Identity, contacts, addresses, tax profile, credit profile, outstanding AR/AP, recent transactions, aging summary, payment information, and sales/purchasing information. This replaces the old permanent customer/vendor snapshot in the header/right rail. |
| Workflow | Status-flow visualization with allowed next transitions | All | Dedicated tab. The header only keeps compact current-state chips; it does not permanently render the lifecycle path. |
| Attachments | Supporting files (supplier invoice scan, OR image, contract) | All | No storage integration exists today anywhere except the CAS attachment register; Phase 2+. BIR substantiation makes this High value for VB/PV/CV. |
| Notes | Internal remarks thread | All | Today a single `remarks`/`memo` field exists; keep the field, add threaded notes only when requested. |
| System Information | IDs, source line provenance, number-series info, fiscal period, snapshot/hash links | All | Collapsed; auditors and support only (role-gated visibility). |

Recommended additional tab: **Compliance Evidence** for documents that feed frozen exports — lists the `report_snapshots` (SAWT/QAP/SLSP/books/CAS) whose frozen payloads include this document, with hash + version. PXL already has the snapshot reader (PXL-DA-015); this tab is the per-document drillback into it. No other ERP-standard tab is missing for PXL's scope.

Not applicable / deferred by type:

- **JE**: no Tax Impact (posts no tax rows), no "GL Impact" (is the GL), Approval tab pending manual-JE approval policy (PXL-DA-012 residue).
- **Vendor Credit / CM / DM**: Approval tab per configured workflow only; Related Documents is the application history (already partially modeled).
- **Cash Sale / Cash Purchase**: single-step post — Approval tab hidden unless a workflow is configured.

## 5. Standard Line Grid

One shared grid component (revive the dead `DataTable`, extend for editing) with column groups. Visibility: **R** required, **O** optional (on by default), **H** hidden by default (column picker), **X** not applicable. "Auto" = populated by the system, editable only where noted.

Current implementation direction: the transaction line grid is the reusable enterprise table framework. It supports system views (**Default, Accounting, Tax, Audit, Inventory, Sales, Custom**), user-saved custom views, persisted visible columns/order/widths/pinned columns/density/sort/filter state, grouped column chooser with search and reset actions, drag-and-drop ordering, column resizing, compact/comfortable/spacious density, export, refresh, sticky headers/totals, and sticky pinned identity columns. Future transaction modules must adopt this framework instead of rebuilding table controls.

| Column | Group | SI / Cash Sale | VB / Cash Purchase | OR | PV | JE | CM/DM | VC |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Item / Service (lookup) | Business | R (auto-fills desc/UOM/price/VAT/account) | O | X | X | X | O | O |
| Description | Business | R | R | X | X | R | R | R |
| UOM | Business | O auto from item | O auto | X | X | X | H | H |
| Qty | Business | R | R | X | X | X | O | O |
| Unit Price | Business | R auto from item, editable | R | X | X | X | O | O |
| Discount % / Amount | Business | O | O | X | X | X | H | H |
| VAT Code | Business | R auto from item/customer profile | R auto from item/supplier profile | X | X | X | R | R |
| VAT Amount | Business | Auto (server recomputes) | Auto | X | X | X | Auto | Auto |
| Net / Gross | Business | Auto | Auto | Auto | Auto | X | Auto | Auto |
| Applied document (SI/VB lookup) | Reference | X | X | R | R | X | O (source SI) | O (source VB) |
| Balance before / Remaining after | Reference | X | X | Auto | Auto | X | X | Auto |
| ATC (lookup, rate shown) | Withholding | H (informational CWT) | X (EWT is at payment) | R when CWT > 0, auto from customer default | R when EWT > 0, auto from supplier default | X | X | X |
| Withholding Tax Base | Withholding | X | X | R when CWT > 0 (VAT-exclusive; PXL-AUD-031) | R when EWT > 0 (exists: `ewt_tax_base`) | X | X | X |
| Withholding Amount | Withholding | X | X | Auto = base × rate, variance-gated | Auto = base × rate, variance-gated (exists) | X | X | X |
| Income Nature / Variance Reason | Withholding | X | X | O | O (exists) | X | X | X |
| Revenue / Expense account | Accounting | H — auto from item; override role-gated (section 7) | H — auto; override role-gated | X | X | R (JE is the exception: account entry IS the document) | H auto | H auto |
| Branch | Dimensions | Auto from header | Auto | Auto | Auto | O per line (DB supports; UI missing) | Auto | Auto |
| Department / Cost Center | Dimensions | H (Phase 2; DB ready per PXL-DA-017) | H | X | X | O per line | H | H |
| Project / Class / Warehouse / Location | Dimensions | H (future; warehouse only for stock items) | H | X | X | H | X | X |
| Reference / Remarks | Reference | O | O | O | O | O | O | O |
| SO / PO / DR link | Reference | H (when conversion flows land) | H | X | X | X | H | X |
| Status / Lock | System | Auto (posted-lock indicator) | Auto | Auto | Auto | Auto | Auto | Auto |
| Source line / Created-Modified | System | H (System Info tab) | H | H | H | H | H | H |

Role-specific: accounting-override columns (accounts, dimensions) visible to accountant/admin roles; encoders see business + withholding groups only. All monetary cells use `AmountCell` (mono, tabular); grids are keyboard-first (Tab/Enter row navigation, F4 lookup).

## 6. Auto-Population Standard

The rule: **the user enters a fact once; everything derivable is derived — visibly.** Each auto-filled field shows provenance on hover/focus ("from Supplier default", "from Item master") and, where editable, an override indicator. Server RPCs remain authoritative (they already recompute totals; client prefill is convenience, not truth).

| Source | Populates | Status today |
| --- | --- | --- |
| Company context (`pxl.ctx.*`) | company, branch, currency, date, open fiscal period | Done (session 44) |
| Customer | name/TIN snapshots, terms, tax type, CWT flag + default ATC, AR account override, address | Mostly done; two CWT flags need merging (PXL-AUD-044); SI expected CWT should flow to OR (PXL-AUD-045) |
| Supplier | name/TIN snapshots, terms, tax type, EWT flag + default ATC, expense mapping | ATC default done; expense mapping not modeled |
| Item / Service | description, UOM, price, VAT code, revenue/expense/inventory account | Done for items on SI/VB; service-type account mapping not modeled |
| Applied SI/VB | balance, default payment = remaining, withholding base = **VAT-exclusive proportion** of amount applied, ATC from counterparty | Balance/payment done; base defaults are gross — must change with PXL-AUD-031/045 |
| SO / PO / DR | full line copy-down on conversion | Conversion flows partial (matrix: quotation/SO/DR rows) |
| Accounting configuration | control accounts (AR/AP/VAT/EWT/cash), never user-picked | Done |
| Number series | document number at save | Done (`fn_next_document_number`) |
| Compliance profile | which tax fields/tabs exist at all (VAT vs non-VAT done; EWT gating missing — PXL-AUD-042) | Partial |

Every field NOT in this table that a user must type is a candidate defect in a future capture-efficiency review.

## 7. Account Determination Standard

Target: **normal users never select a GL account** (Principle 1 of `PXL_PRINCIPLES.md`). Determination ladder, first match wins:

1. Document-line override (accountant/admin role only, logged, visually flagged).
2. Item / service master account (`revenue_account_id` / `expense_account_id`).
3. Item-group / service-type mapping (not yet modeled — Phase 2 with PXL-DA-004 posting primitives).
4. Counterparty default account (customer AR override, supplier expense default).
5. Company accounting configuration (control accounts; posting RPCs already enforce).

Current gap: SI/VB expose a per-line account `<select>` to everyone, and approval validates its presence rather than deriving it. JE is the deliberate exception — account entry is the document's purpose, but the picker must become a `LookupDialog` restricted to active postable accounts (it is a bare full-COA `<select>` today). Override gate: `fn_can_perform`-backed action (e.g. `override_line_account`), disabled-not-hidden for other roles.

## 8. Smart Summary Panels

One `FinancialSummaryPanel` component; per-type formula contracts (server-computed at save; the panel never does its own arithmetic beyond display). Withholding lines appear ONLY when the counterparty is withholding-flagged (progressive disclosure).

- **Sales Invoice / Cash Sale**: Subtotal (net) → Discount → VAT-able / Zero-rated / Exempt split → Output VAT → **Invoice Total** → Less expected CWT (informational, net-of-VAT base) → **Expected Net Collectible**. Cash Sale ends: CWT withheld → **Cash Received**.
- **Official Receipt**: Invoice(s) balance → Payment applied → CWT withheld (base shown) → Forex adj → **Remaining balance per invoice** and total; Cash to deposit.
- **Vendor Bill**: Subtotal → Input VAT → **Bill Total** → Expected EWT (informational) → **Expected Net Payable**.
- **Payment Voucher**: Bill(s) outstanding → EWT withheld (base × rate per ATC) → **Cash to pay** → Remaining per bill. (EWT reduces cash — already correct.)
- **Credit/Debit Memo**: Line totals → VAT effect → **Memo total** → Applied to invoice → Unapplied remainder.
- **Vendor Credit**: Credit total → Applications history → **Remaining balance**.
- **Journal Entry**: Total Debit / Total Credit / **Out-of-balance** (blocking), per-dimension subtotals when dimensions used.

All summary figures are drill sources: clicking Output VAT opens the Tax Impact tab; clicking Remaining opens the application rows.

## 9. GL Impact Standard

`GLImpactPanel` is the right foundation; the standard completes it:

1. **Draft preview** — delivered for saved sources via the PXL-DA-001 rollback preview RPC (same code path as posting); atomic unsaved forms show a clearly labeled client estimate. Account, description, debit, credit, balance, account source, date, period, branch, and rule explanation are shown.
2. **Posted journal** — delivered: JE number/date/lines plus links to JE, GL, account detail, source, and full accounting trace. Reversal-pair presentation remains a layout enhancement.
3. **Drillback** — PXL-DA-002 is Retested Passed: governed source/JE/GL routes and report-family trace sets cover financial, subledger, tax, 2307, and snapshot surfaces. Universal amount-level links and breadcrumb presentation remain Phase 2 layout enhancements.
4. Coverage: broad posting-surface rollout completed in session 59; PXL-AUD-049 remains In Progress only for withholding tax-ledger/2307/QAP drilldown.

## 10. Tax Impact Standard

New `TaxImpactPanel` (does not exist anywhere today). Contents per document:

- Rows from `tax_detail_entries` for this document: tax kind (output VAT / input VAT / EWT payable / CWT receivable), code/ATC, base, rate, amount, reversal state — with counter-rows shown when voided.
- Certificate/report linkage: PV/CV → 2307 issuance (+ status/version), OR → 2307-received tracking, SAWT/QAP/SLSP snapshot versions containing the document (Compliance Evidence tab shares this source).
- Reconciliation state chip: whether the document's period currently reconciles (`fn_vat_gl_reconciliation` / `fn_wht_gl_reconciliation`).
- Correctness dependencies first: the panel must display the **VAT-exclusive withholding base** — building it before PXL-AUD-031/032/033 land would display defective data confidently.

## 11. Posting Validation Standard

`SetupReadinessBanner` extended into a uniform checklist shown on every posting document (not just the core four): company/branch selected · fiscal period open for the document date · number series active · GL posting config complete (per-doc account list) · counterparty active + compliance-complete (TIN when withholding) · tax profile permits the tax codes used · approval satisfied (SoD) · role may post (`fn_can_perform`). Each check mirrors a server-side trigger/RPC validation — the checklist explains in advance exactly what the database will reject (checks and triggers must share definitions, not drift). JE page adopts it too (period + balance + postable accounts).

## 12. Related Documents and Drill Contract

Chains (forward ↓ / backward ↑ everywhere):

- **Sales**: Quotation → SO → DR → SI → OR (→ deposit) → JE → VAT/SAWT returns & books snapshots. CM/DM branch off SI.
- **Purchasing**: PR → PO → (receipt) → VB → PV/CV → JE → 2307 → QAP/1601EQ & books. VC branches off VB.
- **JE**: JE ↔ source document ↔ reversal JE; manual JEs ↔ recurring template.

Contract (PXL-DA-002 owns the enforcement): every JE stores its source (`reference_doc_type/id` — exists); every application row links both documents (exists); every report/export row must carry enough keys to open its source document; every document number rendered anywhere is a link. The Related Documents tab renders this graph — nothing new is stored, it reads existing links.

## 13. Audit Trail and Workflow Standard

Every document view exposes Prepared/Created by+at · Last edited by+at · Approved by+at (and SoD identity) · Posted by+at · Voided/Cancelled by+at + reason code + memo · Lock status (draft-editable vs frozen by PXL-DA-011 guards) in the Audit and Workflow/Approval tabs, not in the permanent header. Below the facts, the `AuditTrailSection` renders `sys_audit_logs` history (component exists, unused — PXL-AUD-050). Workflow: the Workflow tab shows the document's actual flow (from the matrix status columns) with the current state highlighted and permitted transitions represented by the enabled toolbar actions; statuses Draft / Submitted / Approved / Rejected / Posted / Cancelled / Voided / Reversed / Bounced render through the shared status vocabulary.

## 14. Configurable Experience

Phase-2+ configuration surface, in priority order: (1) column picker per grid with hidden-by-default groups (section 5) and per-user persistence (`pxl.ctx.*` pattern); (2) saved list views (filters + columns + sort); (3) role presets — Encoder (business columns), Accountant (+ accounting/dimensions), Auditor (read-only + all evidence tabs expanded); (4) compact/comfortable density toggle; (5) per-company tab visibility driven by `sys_feature_enablement` and the compliance profile (a non-VAT company never sees VAT columns — enforcement layer already exists for VAT; EWT pending PXL-AUD-042). Tab/column configuration is display-only and must never gate server-side validation.

## 15. Reusable Component Inventory

| Component | Status | Standard role |
| --- | --- | --- |
| `GLImpactPanel` | Broadly adopted; exact saved-source preview | Keep; converge placement under `DocumentLayout`; extend report/compliance trace via PXL-DA-002 |
| `SetupReadinessBanner` + `useTransactionReadiness` | Core + VAT-bearing pages; aggregate Company Checklist exists | Extend numbered-document checks under PXL-AUD-016; converge presentation |
| `VATReconciliationPanel` | Exists (VAT pages) | Pattern donor for Tax Impact reconciliation chip |
| `StatusBadge`, `AmountCell`, `DateCell` | Exist, adopted | Keep as the atoms |
| `DataTable`, `LookupDialog`, `FormSection`, `ConfirmDialog`, `EmptyState`, `AuditTrailSection` | Built; `AuditTrailSection` adopted on core transaction pages, others uneven | Revive deliberately: adopt-on-touch; extend DataTable for editable grids |
| `DocumentLayout` (header bar + toolbar + tabs shell) | Missing | Build first — everything else slots into it |
| `FinancialSummaryPanel` | Missing | Section 8 contracts |
| `TaxImpactPanel` | Missing | Section 10 |
| `RelatedDocumentsTab` | Missing | Section 12 (reads existing links) |
| `WorkflowStrip` | Missing | Section 13 |
| `LineGrid` (editable, column groups, keyboard-first) | Missing | Section 5; largest build item |
| Counterparty insight side panel | Missing | Backlog (customer/supplier insights) |

## 16. Gap Analysis Against This Standard

| Standard element | Core four (SI/OR/VB/PV) | JE | CM/DM/VC/Cash/CV |
| --- | --- | --- | --- |
| Per-document routes / deep links | ✗ modal-only | ✗ | ✗ |
| Document header + fixed toolbar + workflow strip | partial (ad hoc) | partial | partial |
| Line grid vs section 5 | partial (business cols; manual account picks; no dimensions) | partial (no dimensions UI) | partial |
| Financial summary contract | ✓ mostly | ✓ balance | ✗/partial |
| GL Impact | ✓ (client preview) | n/a | ✗ (PXL-AUD-049) |
| Tax Impact | ✗ | n/a | ✗ |
| Posting validation | ✓ | ✗ | ✗ |
| Approval visibility | ✗ (DB-only) | ✗ | ✗ |
| Audit trail visibility | ✗ (PXL-AUD-050) | ✗ | ✗ |
| Related documents | partial (application grids) | partial (source ref) | partial |
| Attachments / timeline / config | ✗ | ✗ | ✗ |

## 17. Adoption Sequence and Future Readiness

Phase 2 build order (after current Critical/High findings close): 1) `DocumentLayout` + routes on ONE pilot (Sales Invoice) with tabs shell, audit tab, workflow strip; 2) server-side GL preview (PXL-DA-001) into `GLImpactPanel`; 3) `TaxImpactPanel` (after PXL-AUD-031/032/033); 4) `LineGrid` with account-determination ladder; 5) roll DocumentLayout across the core four, then secondary documents; 6) related-documents tab on the PXL-DA-002 contract; 7) configuration layer. Future capabilities the layout must not preclude (reserved zones, no work now): AI assistant panel (draft/validate/explain — matrix "Future AI Transaction" row), variance analysis on summary panels, cash forecast from open AR/AP, approval timeline (workflow engine), snapshot comparison / document diff (report_snapshots versions already support it), GL/Tax drill-through federated search.

## 18. Cross-References

- Findings: PXL-AUD-050 (audit visibility, new — session 48), PXL-AUD-049 (GL panels), PXL-AUD-042/044/045 (profile gating, duplicate flags, gross defaults), PXL-AUD-016 (readiness rollout), PXL-DA-001 (server GL preview), PXL-DA-002 (drill contract), PXL-DA-004 (posting primitives), PXL-DA-012 (approval SoD residue), PXL-DA-016 (transaction events timeline), PXL-DA-017 (dimensions).
- Backlog: every enhancement row in `PXL_PRODUCT_BACKLOG.md` §Cross-Module maps into a section here; the backlog keeps priority/complexity metadata, this document keeps the design.
- Decisions: DEC-002 (immutability → lock status display), DEC-005 (profile-driven scope → tab/column gating), DEC-009/010 (permissions/SoD → approval tab), DEC-011 (branch dimension), DEC-012 (this document is architecture, not a work order).
