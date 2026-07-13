# PXL Transaction Workspace Standard

Status: **OFFICIAL CANONICAL TRANSACTION WORKSPACE STANDARD**
Canonical reference implementation: **Sales Invoice Workspace** (`/sales-invoices/:id`, `src/pages/SalesInvoiceDocumentPage.tsx`)
Last updated: 2026-07-13

This document is the governing standard for all future PXL transaction workspaces. Do not implement Purchase Invoice, Sales Order, Purchase Order, Delivery Receipt, Official Receipt, Credit Memo, Debit Memo, Journal Entry, Inventory Transactions, Banking, Fixed Assets, Payroll, or Compliance Registers by inventing a new page shape. Future transaction screens must inherit this architecture and extend it only where the document type genuinely requires it.

Current rollout gate: **PXL Accounting Core Ready** (`PXL_ACCOUNTING_CORE_READINESS.md`, DEC-017) must be cleared before expanding this workspace to additional transaction types. This standard remains the UI/UX reference, but accounting engine, tax engine, and master-data governance now take priority over rollout.

## 1. Document hierarchy and authority

1. `PXL_ACCOUNTING_RULES_MATRIX.md` defines governed debit/credit behavior, account determination, tax impact, reversal/void/cancel rules, lock behavior, report impact, and test expectations.
2. `PXL_TRANSACTION_MATRIX.md` + database migrations define transaction lifecycle behavior, statuses, compliance controls, source chains, and data contracts.
3. **This document** defines the official transaction workspace architecture, UX rationale, component standard, and implementation pattern.
4. `PXL_TRANSACTION_EXPERIENCE_STANDARD.md` contains lower-level design details and maturity tracking. When it conflicts with this document, update it to match this document.
5. `UI_UX_PRINCIPLES.md` defines broad visual/interaction principles. Its stack notes are aspirational unless already adopted.
6. `PXL_PRODUCT_BACKLOG.md` holds feature-level rollout planning and deferred enhancements.

Routing rule for discoveries during workspace work:

- Functional/accounting/tax/security bugs → `PXL_END_TO_END_AUDIT_FINDINGS.md`
- Architectural/product enhancements → this document or `PXL_PRODUCT_BACKLOG.md`
- Permanent architectural decisions → `AI/AI_DECISIONS.md`

## 2. Overall workspace philosophy

The PXL transaction workspace is modeled after mature enterprise ERP systems: Oracle NetSuite, SAP Business One, Microsoft Dynamics 365 Business Central, and Oracle Fusion. It must feel like an accounting operations surface, not a custom CRUD form.

The user should be able to answer these questions without leaving the workspace:

- What document am I looking at?
- Who is the counterparty?
- What is the amount, collection/payment state, and outstanding balance?
- Is the document editable, posted, frozen, voided, paid, or partially paid?
- What line items, accounts, tax codes, dimensions, and source references produced this document?
- What GL and tax impact does it create?
- What validation checks passed or failed?
- Who created, edited, approved, posted, paid, voided, or restored it?
- What documents came before and after it?
- What supporting files, notes, activity, and technical metadata exist?

The workspace is divided into four major layers:

1. **Header** — immediate identity, state, KPIs, and actions.
2. **Information cards** — compact transaction facts needed before inspecting tabs.
3. **Tabs** — single-responsibility perspectives: lines, accounting, tax, validation, workflow, audit, related documents, party profile, attachments, activity, notes, and system metadata.
4. **Detail area** — the active tab content, including expandable line detail and drilldowns.

This organization reduces scrolling, avoids duplicated information, and keeps each data category in one predictable home. It also lets accountants, tax reviewers, approvers, inventory users, auditors, and support staff use the same page without turning the header into a master-data dump.

Core principles:

- One routed workspace per transaction.
- No separate “View” and “Open” pages.
- No right rail for duplicate summaries.
- No Quick Actions card.
- Actions live only in the header toolbar.
- Workflow lives in Workflow / Approval.
- Accounting lives in GL Impact.
- Tax lives in Tax Impact.
- Audit lives in Audit / System.
- Customer/vendor detail lives in Related Party.
- Related documents live in Related Documents.
- Master data lives in master records and is referenced by transactions.

## 3. Standard workspace anatomy

Every transaction workspace follows this structure:

```text
Breadcrumb / route context

Document Header
  Document number
  Document status chip
  Posting / Collection-Payment / Lock chips
  Counterparty link
  Primary KPIs
  Header toolbar

Primary Information Band
  Document Information
  Customer/Vendor/Party Information
  Transaction Context

Tab Bar
  Lines | Financial | GL Impact | Tax Impact | Validation | Workflow | Approval |
  Audit | Related Docs | Related Party | Attachments | Activity | Notes | System

Active Tab Content

Footer Metadata
```

The structure may hide tabs that are truly not applicable, but it must not invent a different page architecture for each module.

## 4. Header standard

### Purpose

The header identifies the document, communicates current state, shows the primary monetary facts, and exposes document actions. It is not a party profile, audit report, workflow timeline, GL view, or system metadata panel.

### Required header content

- Document type label, e.g. `Sales Invoice`.
- Large document number, e.g. `SI-2026-000001`.
- Main document status, e.g. `Posted`, `Draft`, `Voided`.
- Three compact status chips:
  - **Posting** — posted/unposted/voided, usually represented by the main status chip.
  - **Collection or Payment** — open, partially paid, paid, not posted, unapplied, etc.
  - **Lock** — editable/frozen/locked.
- Clickable counterparty name when applicable.
- Primary KPIs:
  - Sales Invoice: Invoice Total, Collected, Balance Due.
  - Vendor Bill: Bill Total, Paid, Balance Due.
  - Official Receipt: Receipt Total, Applied, Unapplied.
  - Journal Entry: Debit, Credit, Difference.
- Header toolbar.

### Header toolbar

The toolbar is the single source of document actions.

Standard visible toolbar hierarchy:

1. Primary lifecycle or processing action, e.g. Create Receipt, Post, Submit, Approve.
2. Print.
3. Email.
4. More.

Rules:

- At most three primary buttons plus `More`.
- Destructive or lower-frequency actions live under `More`.
- Inapplicable actions are disabled when useful for discoverability.
- Actions are status-aware and permission-aware.
- The `More` menu must render through a portal/fixed positioning so it is never clipped by parent overflow.

Common actions:

- Submit / Approve / Post / Return to Draft.
- Create Receipt / Create Credit Memo / Create Debit Memo.
- Print.
- Email.
- Void / Cancel / Reverse.
- Open Customer / Supplier.
- Open Journal Entry.
- Open Full Accounting Trace.
- View Ledger.
- View Tax Ledger.
- Generate E-Invoice, if configured.

### What must never be duplicated in the header

Do not permanently display these in the header:

- Workflow path or workflow history.
- Created by / modified by / posted by.
- Source type.
- Document series.
- Official receipt / payment links.
- Full customer/vendor contact data.
- Credit limit, available credit, outstanding AR/AP, aging.
- GL lines or posting rules.
- Tax ledger detail.
- Attachments, notes, or activity history.
- UUIDs, RPC names, engine versions, hashes, migration IDs.

Those belong in their dedicated tabs.

### Status chips

Status chips must be compact and state-driven:

- Success → green.
- Warning/locked → orange.
- Error/voided/rejected → red.
- Informational/open → blue.
- Neutral/inactive/unavailable → gray.

Inactive lifecycle steps must remain gray. Do not use color decoratively.

## 5. Information card standard

The information band is exactly three compact cards below the header:

1. **Document Information**
2. **Customer/Vendor/Party Information**
3. **Transaction Context**

Cards use identical padding, spacing, title style, label style, and value alignment. They are not mini dashboards.

### Document Information

Purpose: immediate transaction facts required to understand the document before inspecting tabs.

Sales Invoice keeps:

- Invoice Date.
- Due Date.
- Branch.
- Currency.
- Payment Terms.
- Reference, when present.

Equivalent document-specific fields are allowed, e.g. receipt date, bill date, posting date, transfer date.

Do not put these here:

- Source Type → System.
- Document Series → System.
- Official Receipt / payment link → Related Documents.
- Created By / Modified By → Audit.
- Posting engine/hash/version → System.

### Customer/Vendor/Party Information

Purpose: identify the counterparty and expose the critical tax identity needed for the transaction.

Sales Invoice keeps:

- Customer, clickable to the Customer master.
- Customer Code.
- TIN.
- VAT Classification.

Equivalent supplier/employee/bank/asset party identifiers are allowed by document type.

Do not put these here:

- Contact, email, phone.
- Registered/delivery address.
- Credit limit, available credit.
- Outstanding AR/AP.
- Customer group, price level, territory, industry.
- Customer since, last payment.
- Recent invoices/payments/bills.

Those belong in Related Party or the party master.

### Transaction Context

Purpose: dimensions and operational context that affect posting or responsibility.

Sales Invoice keeps:

- Salesperson.
- Project.
- Cost Center.
- Department.

Equivalent document-specific posting dimensions may appear here. If a field does not exist as governed master data, display it truthfully as unassigned/untracked and add the proper master-data gap. Do not hardcode static values into the transaction page.

Do not put these here:

- Source Sales Order / delivery receipt → Related Documents.
- Price list / payment method / delivery terms → Related Party or document-specific tab.
- Campaign / opportunity → future Marketing module.
- Full dimension breakdown → line detail or future Dimensions tab.

### Clickable master data links

- Counterparty names link to the master record.
- Account codes link to account detail / ledger where available.
- Journal numbers link to Journal Entry or Accounting Trace.
- Related document numbers link to their canonical workspace.
- Links must not open duplicate view pages.

## 6. Tab architecture

Tabs are perspectives on the same transaction. Each tab has a single responsibility, a compact section header, and a consistent table/card visual system.

Standard tab set:

1. Lines.
2. Financial.
3. GL Impact.
4. Tax Impact.
5. Validation.
6. Workflow.
7. Approval.
8. Audit.
9. Related Docs.
10. Related Party.
11. Attachments.
12. Activity.
13. Notes.
14. System.

Future tabs may be added only when the data cannot reasonably fit one of these responsibilities, e.g. Compliance Evidence, Dimensions, or Revenue Recognition. Do not add document-specific tabs for information that already has a standard home.

### Tab specification table

| Tab | Business purpose | Intended users | Data ownership | Required fields/data | Optional fields/data | Navigation rules | Audit expectations |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lines | Primary economic facts of the transaction. | Accountants, encoders, auditors, inventory users, tax users. | Transaction lines plus item/account/tax/dimension masters. | Line number, item/service/description, quantity or amount, UOM when relevant, price/rate, net, tax code, tax amount, total. | Discounts, withholding, dimensions, warehouse, remarks, reference, source line, audit metadata. | Row click expands detail; linked item/account/source docs open canonical routes. | Every saved line must expose created/updated facts and posting rule provenance when available. |
| Financial | Accounting summary of computed totals. | Accountants, reviewers, finance managers. | Server-computed transaction totals and collection/payment applications. | Gross, discounts, net, VAT, total, paid/applied, balance. | Deferred/realized revenue, rounding, currency difference, expected withholding. | No duplicate header KPIs beyond detail breakdown. | Must state when values are untracked/unavailable rather than fabricated. |
| GL Impact | Debit/credit effect and journal linkage. | Accountants, auditors, approvers. | Posting engine, preview RPC, journal entries, chart of accounts. | Account code/name, description, debit, credit, source, posting rule, journal link, balanced state. | Dimensions, created-by-rule, branch, project, cost center. | Account opens ledger/detail; JE opens Journal Entry/Accounting Trace. | Must come from authoritative posting preview/posted JE; never client-only accounting logic. |
| Tax Impact | Tax ledger entries and compliance linkage. | Tax users, accountants, auditors. | Tax engine, tax detail entries, VAT/ATC/tax code masters. | Tax type, VAT/ATC, base, rate, amount, status, source rule. | Recoverable/payable split, BIR return, SAWT/QAP/2307 linkage. | Tax ledger entry opens tax detail where available; reports link to tax reviews. | Must clearly mark draft estimates and deferred tax types. |
| Validation | Posting readiness and blockers. | Accountants, approvers, support. | Readiness hooks, server validation rules, posting RPC requirements. | Balanced, period open, branch active, series valid, tax valid, approval passed, line presence. | Engine version, hash, inventory/cost posted. | Blocker labels should guide user to the setup/document area that fixes them. | Must mirror server-side validation definitions; no drift. |
| Workflow | Lifecycle stage. | Encoders, approvers, accountants. | Document status fields and workflow instances. | Draft/approved/posted/paid/voided stage state. | Stage actor/date when stored. | Toolbar actions represent permitted transitions; history belongs here/Approval, not header. | State changes must be reflected in Audit. |
| Approval | Authorization history. | Approvers, auditors, accountants. | Approval instances/workflow tables. | Level, approver, role, action/status, date. | Remarks, electronic signature, delegation. | Approver/user links when available. | Must show no-workflow empty state compactly and truthfully. |
| Audit | Chronological audit trail. | Auditors, support, controllers. | System audit logs plus document lifecycle fields. | Created, edited, approved, posted, voided/restored events; user; timestamp. | IP, device, changed fields, old/new values. | User/device details are display-only; source rows link where appropriate. | Audit trail must be immutable/server-owned where compliance requires. |
| Related Docs | Upstream/downstream document chain. | All transaction users. | Document links, source references, application lines, JE links. | Relationship, type, doc number, status, amount, direction, action. | Graph display, missing-stage reasons. | Every existing document number opens its canonical workspace; missing stages show “Not linked/Not created.” | Chain must support drilldown/drillback and never hide missing expected stages silently. |
| Related Party | Embedded counterparty profile snapshot. | AR/AP, collections, purchasing, sales, tax. | Customer/supplier/party master plus AR/AP aging and recent docs. | Identity, contacts, addresses, tax profile, credit profile, outstanding balance. | Recent invoices/payments/bills, aging buckets, payment info, sales/purchasing info. | Party name opens master record; recent docs open canonical routes. | Transaction should indicate when master record is unavailable and show saved snapshot where applicable. |
| Attachments | Supporting files. | Accountants, auditors, compliance users. | Attachment register/storage/OCR subsystem. | File, type, uploaded by, date, preview/download action, OCR status. | Source document scan, BIR docs, delivery proof, approvals. | Preview/download must use governed storage URLs. | Upload/download/OCR events should appear in Activity/Audit when implemented. |
| Activity | Business/system event timeline. | Accountants, support, managers. | Transaction event stream, email/notification/API logs. | Created, approved, posted, printed, emailed, collected, voided. | Integration/API events, comments, notifications. | Linked events open source artifacts where available. | System events must be timestamped and attributable where possible. |
| Notes | Human-entered notes by category. | Accountants, collections, customer/vendor support. | Note tables or document memo fields. | Internal, customer/vendor, accounting, collection notes. | Threaded comments, mentions, attachments. | Notes remain in the transaction; public-facing notes must be clearly separated. | Edits should be auditable once persisted as note entities. |
| System | Technical metadata only. | Support, developers, auditors when needed. | Database IDs, RPC names, engine versions, hashes, migration metadata. | UUID, database ID, source module/type, RPC names, timestamps, internal IDs. | Engine versions, hash, migration version, internal references. | No daily business actions here. | Values must be factual and useful for support/audit traceability. |

## 7. Lines tab and Smart Grid standard

The Lines tab is the most important daily-use tab. It must behave like an enterprise accounting grid, not a simple HTML table.

### Required grid behavior

- One shared component framework: `LineGrid`.
- Compact density by default.
- Sticky header.
- Sticky totals row when totals exist.
- Sticky pinned identity columns.
- Smooth horizontal scroll for wide accounting tables.
- Row hover state.
- Numeric values right-aligned and tabular.
- Totals emphasized but not oversized.
- Empty states compact and professional.
- Loading states compact and non-decorative.
- Column resizing with stable widths.
- Column sorting where a sort value exists.
- Global visible-column filter.
- CSV export of visible rows/columns.
- Refresh hook supplied by the owning page.

### Saved views

Every transaction line grid must support these system views where applicable:

- Default.
- Accounting.
- Tax.
- Audit.
- Inventory.
- Sales.
- Custom.

Users may save current configuration, update saved views, rename saved views, delete custom views, reset to current view, and reset to system default.

Persist per workspace/table key:

- Selected view.
- Visible columns.
- Column order.
- Pinned columns.
- Column widths.
- Density.
- Sorting.
- Filters.
- Custom saved views.

Current implementation persists in browser `localStorage`. A future cross-device preference store may be added as a separate governed feature, but future pages must still use the same interface contract.

### Column chooser

The chooser must include:

- Search.
- Select All.
- Clear All.
- Reset to Current View.
- Reset to System Default.
- Grouped column list.
- Visible column drag-and-drop ordering.
- Pin/unpin controls.
- Save/update/rename/delete view actions.

Standard column groups:

- General.
- Sales.
- Inventory.
- Tax.
- Accounting.
- Dimensions.
- Audit.
- System.

### Pinned/frozen columns

Default pinned columns for line-based documents:

- `#`
- Item Code or Account Code.
- Description.

Pinned columns may be unpinned by the user when the component allows it. Pinned columns must remain sticky while horizontally scrolling.

### Expand row behavior

Every row may expand to a line detail panel. The expanded panel keeps the main grid uncluttered.

Expected line detail sections:

- Revenue/expense/cost recognition.
- Serial numbers.
- Lots.
- Inventory allocation.
- Dimensions.
- Tax breakdown.
- Audit information.
- Source references.
- Posting rule used.
- Related documents.
- Item/service notes.

If data is not stored yet, display “Not linked,” “Not recorded,” or “Not assigned.” Do not invent data.

### Reuse across transaction types

Future transaction workspaces must configure `LineGrid` through column definitions, system views, saved-view key, and renderers. They must not fork a new table system for each module.

Examples:

- Official Receipt / Vendor Payment: application grid for invoices/bills applied.
- Journal Entry: debit/credit account entry grid.
- Inventory Transfer: item/warehouse/lot/serial movement grid.
- Fixed Asset Acquisition: asset/cost/capitalization grid.
- Payroll Posting: employee/component/account allocation grid.

## 8. Accounting and supporting tab standards

### Financial Summary

Financial Summary is a computed accounting summary, not a duplicate of header KPIs.

Rules:

- Use `FinancialSummaryPanel`.
- Document type owns the summary contract.
- Server totals are preferred.
- Distinguish gross, discounts, net, tax, withholding, collections/payments, remaining balance, rounding, and currency differences.
- Show untracked values as untracked/unavailable.

### GL Impact

GL Impact is the accounting truth view.

Rules:

- Use authoritative posting preview/posted journal data.
- Do not calculate production accounting impact only on the client.
- Show balanced/out-of-balance status.
- Show account code/name, debit, credit, source, posting rule, dimensions, and journal link.
- JE links open Journal Entry/Accounting Trace.
- Account links open account detail/ledger where available.

### Tax Impact

Tax Impact is the tax ledger/compliance view.

Rules:

- Use tax ledger/detail entries and tax master data.
- Show draft estimates only when clearly labeled.
- VAT, EWT/CWT, ATC, tax base, rate, amount, recoverable/payable, BIR return, status, and source rule belong here.
- Do not mix tax totals into the header.

### Validation

Validation explains whether the document can be posted.

Rules:

- Use `PostingValidationPanel`.
- Mirror server-side validation.
- Show success/warning/error/info indicators compactly.
- Do not use validation as a substitute for server enforcement.

### Workflow and Approval

Workflow shows lifecycle. Approval shows authorization.

Rules:

- Current status may appear in the header chip.
- Full lifecycle path belongs in Workflow.
- Approver/action/date/remarks/signature belong in Approval.
- Approval absence must show a compact empty state.

### Audit

Audit shows lifecycle facts plus chronological system audit history.

Rules:

- Created/edited/approved/posted/voided/restored facts belong here.
- IP/device/changed fields belong here where available.
- Do not duplicate audit facts in header/cards.

### Related Documents

Related Docs shows the full expected chain.

Rules:

- Use `RelatedDocumentsTab`.
- Existing docs are clickable.
- Missing expected docs show a row with “Not linked,” “Not created,” or equivalent.
- Do not hide missing stages silently.
- Chains must support upstream and downstream navigation.

Sales example:

```text
Quotation → Sales Order → Delivery Receipt → Sales Invoice → Official Receipt → Journal Entry
                                ↘ Credit Memo / Debit Memo / Customer Return
```

Purchasing example:

```text
Purchase Request → Purchase Order → Receiving Report → Vendor Bill → Payment Voucher → Journal Entry
                                                   ↘ Vendor Credit / Purchase Return / 2307
```

### Related Party

Related Party is the embedded live master profile.

Rules:

- Customer/vendor master details belong here, not in the header.
- Show identity, contacts, addresses, tax profile, credit profile, outstanding AR/AP, recent transactions, aging, payment/sales/purchasing info.
- The party name links to the master record.
- When the master is unavailable, show a compact empty state and preserve transaction snapshot facts where available.

### Attachments

Attachments show supporting files only.

Rules:

- Table columns: File, Type, Uploaded By, Date, Preview, Download, OCR Status.
- Storage/OCR must be governed. Do not fake attachment availability.
- Empty state is compact.

### Activity

Activity is the business/system event stream.

Rules:

- Include emails, comments, workflow, system events, API events, integrations, notifications.
- Lifecycle facts may be shown until a semantic event stream exists.
- Activity must not replace Audit.

### Notes

Notes separate internal/customer/accounting/collection notes.

Rules:

- Separate public/customer notes from internal notes.
- Show compact “No notes recorded” states.
- Persisted note edits should become auditable when note storage is implemented.

### System

System is technical metadata only.

Rules:

- UUID, database ID, RPC names, posting/tax engine versions, hash, source module/type, migration version, created/updated timestamps, internal IDs.
- Business users should not need this tab daily.
- Do not put business workflow or party data here.

## 9. UI/UX standards

### Visual style

- Enterprise ERP, not consumer SaaS.
- Small border radius: 2-4px.
- Thin neutral borders.
- Minimal shadows.
- Subtle separators.
- Tight but readable spacing.
- No decorative widgets.
- Cards remain white.
- Workspace background uses a 2-3% tint of the company accent color.
- Header uses the company-selected accent color.
- Tab strip uses a very light accent tint.

### Typography

Strong emphasis is limited to:

- Document number.
- Totals.
- Section titles.
- Active tab.
- Status badges.

Most labels and values use regular or medium weight. Hierarchy comes from size, spacing, color, alignment, and structure rather than excessive bolding.

### Color

Only use color to communicate state or interaction:

- Success → green.
- Warning/locked → orange.
- Error/destructive → red.
- Informational/open/link → blue.
- Neutral/inactive/unavailable → gray.

Inactive workflow steps are gray.

### Tables

All tables use the same design system:

- Compact row height.
- Compact uppercase headers.
- Thin row separators.
- Numeric right alignment.
- Tabular numbers for amounts.
- Hover state.
- Compact empty state.
- Total row with subtle background.
- Status badges consistent with shared `StatusBadge`.

### Empty states

Empty states must be concise and professional:

- “No approval workflow configured.”
- “No attachments linked to this invoice.”
- “No VAT ledger rows for this document.”
- “Customer master record unavailable.”

Avoid debug wording, oversized blank panels, and playful language.

### Loading states

Loading states are compact text states unless a full-page load is unavoidable. Do not add skeleton decoration unless it materially improves usability.

### Responsive behavior

- Header may stack on smaller screens but should remain compact.
- Tabs stay one line and truncate labels before overflowing.
- Wide tables scroll horizontally.
- Pinned columns remain usable during horizontal scroll.
- Cards collapse from three columns to fewer columns on narrower screens.

### Accessibility

- Buttons have semantic labels or titles where icon-only.
- Tabs use `role="tab"` / `aria-selected` where implemented.
- Expandable rows use `aria-expanded`.
- Disabled actions remain visibly disabled.
- Color is not the only indicator: labels and text must communicate status.

## 10. Reusable component inventory

Current reusable components and intended responsibilities:

| Component / target | Current file | Responsibility |
| --- | --- | --- |
| Transaction Header / shell | `src/components/document/DocumentLayout.tsx` | Header, toolbar, status chips, tab bar, workspace tint, footer slot. |
| Header toolbar / More menu | `DocumentLayout.tsx` | Status-aware actions, primary action limit, portal More menu. |
| KPI Summary | `DocumentLayout.tsx` metrics contract | Header primary metrics only. |
| Information Cards | `src/components/document/PrimaryInformationPanel.tsx` | Three-card information band. |
| Tab Container | `DocumentLayout.tsx` (`TransactionTabsBar`, `TransactionTabs`) | Compact one-line tab navigation. |
| Smart Grid / Saved Views | `src/components/document/LineGrid.tsx` | Enterprise table framework, saved views, chooser, resize/order/pin/density/filter/export. |
| Column Chooser | `LineGrid.tsx` | Grouped column visibility and saved view controls. |
| Line Detail Panel | `src/components/document/LineDetailPanel.tsx` | Expandable row detail sections. |
| Financial Summary | `src/components/document/FinancialSummaryPanel.tsx` | Per-document computed financial summary. |
| Validation Panel | `src/components/document/PostingValidationPanel.tsx` | Posting/readiness checklist. |
| GL Impact | `src/components/GLImpactPanel.tsx` | Authoritative GL preview/posted impact and JE links. |
| Tax Impact | `src/components/document/TaxImpactPanel.tsx` | Tax ledger view; currently VAT-safe boundary for SI. |
| Related Documents | `src/components/document/RelatedDocumentsTab.tsx` | Upstream/downstream chain skeleton and links. |
| Workflow Timeline | `DocumentLayout.tsx` (`WorkflowStrip`) | Compact lifecycle visualization inside Workflow tab. |
| Audit Timeline | `src/components/ui/shared.tsx` (`AuditTrailSection`) | System audit log table. |
| ERP Section Header / table primitives | `src/components/document/ErpSection.tsx` | Shared section headers, table classes, compact empty states. |
| Attachment Viewer | target component | Future governed attachment table/preview/download/OCR wrapper. |
| Activity Feed | target component | Future semantic event stream renderer. |
| System Information Panel | target component | Future reusable technical metadata table. |

Do not fork these responsibilities into page-local components unless the component is being extracted immediately after the page proves the pattern.

## 11. Extension rules for future transactions

Future transaction pages must extend the standard through configuration and document-specific data contracts, not by redesigning layout.

Rules:

1. Start from `DocumentLayout`.
2. Use exactly three primary information cards unless this document is updated.
3. Use the standard tab set and hide only genuinely irrelevant tabs.
4. Use `LineGrid` for line/application/accounting grids.
5. Use `RelatedDocumentsTab` for chains.
6. Use shared status badges and status vocabulary.
7. Use the header toolbar for actions; do not add a Quick Actions card.
8. Put master-record detail in Related Party.
9. Put GL in GL Impact.
10. Put tax in Tax Impact.
11. Put audit facts in Audit/System.
12. Put technical metadata in System.
13. If a field is reusable or governed, create/extend master data rather than hardcoding transaction-local options.
14. Add document-specific tabs only when the information cannot fit a standard tab and the need applies across a module family.

Examples:

- Purchase Order should reuse the same header/cards/tabs/grid, with Supplier Information and Purchasing Context.
- Official Receipt should reuse the same workspace but configure Lines as an application grid.
- Journal Entry should reuse the shell but configure primary KPIs as Debit/Credit/Difference and omit Tax Impact unless tax rows are explicitly supported.
- Inventory Transfer should use inventory-specific line columns and Related Documents for source/target links.

## 12. Developer guidelines

### Folder structure

Shared transaction components live under:

```text
src/components/document/
```

Canonical routed transaction workspaces live under:

```text
src/pages/*DocumentPage.tsx
```

Registers/list pages remain under:

```text
src/pages/*Page.tsx
```

The target route model:

```text
/module-docs           register/list
/module-docs/new       create in workspace shell
/module-docs/:id       view/review/lifecycle workspace
/module-docs/:id/edit  edit draft in workspace shell
```

### React/TypeScript conventions

- Keep shared component contracts generic and data-agnostic.
- Use TypeScript interfaces for:
  - `DocumentTab`.
  - `ToolbarAction`.
  - `DocumentMetric`.
  - `DocumentMetaField`.
  - `InfoGroup` / `InfoField`.
  - `LineColumn`.
  - `LineColumnProfile`.
  - `RelatedDocRow`.
  - `ValidationCheck`.
- The page owns data loading and maps data into reusable component contracts.
- Shared components should not fetch business data unless their responsibility requires it and the contract is explicitly documented.
- Use truthful unavailable states rather than placeholder business values.

### Data loading pattern

- Load header, lines, master references, related docs, approvals, collections/payments, and party snapshot in one page-level load function where practical.
- Use `Promise.all` for independent reads.
- Keep derived display values near the page mapping layer.
- Server RPCs remain authoritative for posting, validation, GL impact, tax impact, and immutable lifecycle transitions.

### Permissions and actions

- UI gates actions by status for usability.
- Server functions must enforce permissions, segregation of duties, lifecycle immutability, accounting rules, and compliance rules.
- Destructive actions require reason capture where the domain requires it.
- Posted/frozen documents are read-only except for allowed reversal/void/application workflows.

### Testing expectations

For UI-only workspace changes:

- `npm run lint`
- `npm run build`
- `git diff --check`
- Manual route/port check when practical.

For schema/posting/tax changes:

- Add or update pgTAP tests.
- Run relevant Supabase reset/tests only after holding out known user-owned broken drafts when applicable.
- Regenerate types and schema summary when migrations change.
- Never change posting/tax behavior as a side effect of a UI workspace task.

### Naming conventions

- Workspace shell: `DocumentLayout`.
- Routed page: `{DocumentType}DocumentPage`.
- Register/list: `{DocumentType}Page`.
- Tab content variables: `linesTab`, `financialTab`, `glTab`, `taxTab`, etc.
- Related doc rows: `RelatedDocRow[]`.
- Line views: `LineColumnProfile[]`.
- Table storage key: include company and document family, e.g. `company:${companyId}:sales-invoice:lines`.

## 13. Sales Invoice reference implementation

Sales Invoice is the canonical pilot and must be treated as the reference for future document workspaces.

### Route and page

- Route: `/sales-invoices/:id`.
- Page: `src/pages/SalesInvoiceDocumentPage.tsx`.
- Shell: `DocumentLayout`.
- Register routes non-draft rows into this workspace.
- Draft create/edit still uses the register editor until routed consolidation is implemented.

### Header implementation

- Company accent header.
- Document number.
- Posting status as main chip.
- Collection and Lock chips.
- Clickable Customer.
- KPIs: Invoice Total, Collected, Balance Due.
- Toolbar: state-aware Submit/Post/Create Receipt, Print, Email, More.
- More menu uses portal/fixed positioning.

### Primary cards

- Document Information: Invoice Date, Due Date, Branch, Currency, Payment Terms, Reference.
- Customer Information: Customer link, Customer Code, TIN, VAT Classification.
- Sales Context: Salesperson, Project, Cost Center, Department.

### Tabs

Sales Invoice currently implements:

- Lines with saved views and expandable detail.
- Financial Summary.
- GL Impact.
- Tax Impact.
- Validation.
- Workflow.
- Approval.
- Audit.
- Related Docs.
- Related Party.
- Attachments.
- Activity.
- Notes.
- System.

### Known boundaries in the reference

- Draft create/edit route consolidation remains pending.
- Tax Impact is VAT-safe only until withholding-base defects are resolved.
- Attachment/OCR storage is not configured.
- Semantic activity event stream is not yet stored.
- Categorized notes are not yet persisted as separate note entities.
- Document hash/version fields are not yet stored.
- E-invoice integration is disabled until provider setup exists.
- Some Sales/Customer/Dimension fields are not yet governed master data links and display as unassigned.

## 14. UX decision log

These decisions are part of the standard. Do not reverse them in future workspaces without updating this document and recording a decision.

| Decision | Rationale |
| --- | --- |
| Use one routed workspace per transaction. | Auditors, approvers, support, and accountants need deep links and one canonical document-of-record surface. |
| Remove separate View/Open pages. | Prevents duplicated UI and inconsistent behavior. |
| Remove right sidebar. | It duplicated Financial Summary, Customer Snapshot, Posting Validation, and Audit Summary already available in tabs/header. |
| Remove Quick Actions card. | Actions already exist in the header toolbar; duplicate actions create confusion. |
| Move workflow path out of header. | Header should show current state only; full lifecycle belongs in Workflow/Approval. |
| Move audit facts out of header/cards. | Audit data belongs in Audit/System; permanent header audit metadata increases height and duplication. |
| Keep only three information cards. | Reduces vertical height and keeps line items visible sooner. |
| Keep Customer/Vendor card minimal. | Transaction page should not copy the party master; Related Party owns the profile. |
| Move Source Type, Document Series, hashes, RPCs to System. | These are technical/support fields, not daily processing facts. |
| Move related-document links to Related Docs. | Related-document ownership must be centralized and clickable in one chain. |
| Header toolbar is the single source of actions. | Prevents duplicate actions and supports status-aware hierarchy. |
| More menu renders through a portal. | Menus must not be clipped by containers in enterprise workflows. |
| Use company accent color only for header/theme tint. | Supports branding while keeping the workspace calm. |
| Use color only for state/interaction. | Enterprise accounting UI should avoid decorative color noise. |
| Standardize table rhythm and section headers. | Every tab must feel like the same ERP application. |
| Upgrade Choose Columns into saved views. | Accountants, auditors, tax users, inventory users, and finance managers need personalized layouts without changing transaction data. |
| Persist table preferences locally for now. | UI-only pass avoided schema/API work; cross-device preferences require a separate governed feature. |
| Display unassigned/untracked values truthfully. | Prevents hardcoded fake master data and protects auditability. |

## 15. Rollout matrix

Adoption: ✅ done · ◐ partial · ⬜ not started.

| Transaction | Canonical route target | Workspace adoption | Notes |
| --- | --- | --- | --- |
| Sales Invoice | `/sales-invoices/:id` | ✅ reference implementation | Draft/new route consolidation pending. |
| Cash Sale | `/cash-sales/:id` | ⬜ | Reuse SI shape with cash-sale-specific KPIs/actions. |
| Receipt / Official Receipt | `/receipts/:id` | ⬜ | Lines become invoice application grid. |
| Credit Memo | `/credit-memos/:id` | ⬜ | Related Docs starts from source SI. |
| Debit Memo | `/debit-memos/:id` | ⬜ | Related Docs starts from source SI. |
| Quotation | `/quotations/:id` | ⬜ | Non-posting; GL/Tax may show not-applicable state. |
| Sales Order | `/sales-orders/:id` | ⬜ | Related chain Quotation → SO → DR/SI. |
| Delivery Receipt | `/delivery-receipts/:id` | ⬜ | Inventory/logistics emphasis. |
| Customer Return | `/customer-returns/:id` | ⬜ | Related to SI/DR and inventory movement. |
| Purchase Order | `/purchase-orders/:id` | ⬜ | Supplier/Purchasing Context. |
| Receiving Report | `/receiving-reports/:id` | ⬜ | Inventory receiving line grid. |
| Vendor Bill / Purchase Invoice | `/vendor-bills/:id` | ⬜ | Recommended next after SI consolidation. |
| Cash Purchase | `/cash-purchases/:id` | ⬜ | Cash purchase KPIs and supplier/tax profile. |
| Payment Voucher | `/payment-vouchers/:id` | ⬜ | Lines become bill application grid. |
| Vendor Credit | `/vendor-credits/:id` | ⬜ | Related to Vendor Bill. |
| Purchase Return | `/purchase-returns/:id` | ⬜ | Related to RR/VB and inventory movement. |
| Journal Entry | `/journal-entries/:id` | ⬜ | Document is the GL entry; omit redundant GL Impact. |
| Inventory Adjustment / Transfer / Count | `/inventory-*/:id` | ⬜ | Use inventory saved views and warehouse/lot/serial line detail. |
| Fixed Asset Acquisition / Depreciation / Disposal | `/fixed-assets/*/:id` | ⬜ | Asset detail and accounting impact through same tabs. |
| Bank Transactions | `/bank-*/*:id` | ⬜ | Banking context and reconciliation links. |
| Payroll Posting | `/payroll-postings/:id` | ⬜ | Payroll components and GL allocation grid. |

## 16. Maintenance

Update this document whenever:

- A transaction workspace pattern changes.
- A reusable component contract changes.
- A tab is added/removed from the standard.
- A major UX decision is made.
- A future module discovers a standard gap.

Keep the subordinate experience blueprint and transaction matrix synchronized after this document changes.
