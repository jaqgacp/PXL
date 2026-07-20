# PXL Standard Report Workspace

Status: Official canonical reporting architecture
Applies to: All current and future PXL ERP reports
Sibling standard: `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md`
Last updated: 2026-07-13

This document defines the official PXL reporting architecture. It is the report-page sibling of the transaction workspace architecture. Future Accounting, Sales, Purchasing, Banking, Inventory, Fixed Assets, Tax, Compliance, Audit, and Management reports must reuse this standard instead of inventing independent report layouts.

This is an architecture and implementation standard. It is not a request to rebuild every report immediately.

Current rollout gate: **PXL Accounting Core Ready** (`docs/PXL/02. Accounting Core/PXL_ACCOUNTING_CORE_READINESS.md`, DEC-017) must be cleared before implementing report pilots or redesigning report pages. This standard remains the reporting architecture reference, but accounting engine, tax engine, reconciliation, and master-data correctness now take priority over report rollout.

Accounting behavior and expected report impact are governed by `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`. Report pages must reconcile to the posting behavior defined there rather than redefining accounting rules inside report code.

## 1. Core reporting philosophy

A report in PXL is not a table with an Export button. A report is an accountable financial view that must explain its purpose, context, source, assumptions, reconciliation status, drill path, reproducibility, and audit trail.

Every report must answer these questions:

- What accounting or operating question does this report answer?
- Which data source is authoritative?
- Which company, branch, consolidation scope, period, currency, and accounting basis are active?
- Which filters are currently applied?
- Does the report reconcile to its control account, source ledger, or authoritative register?
- Can the user drill from summary to detail, journal, source document, source line, and evidence?
- Can the user return to the report without losing filters, mode, sort, or scroll context?
- Can the report be reproduced later?
- Who generated, printed, exported, snapshotted, or filed it?
- Is the report live, saved, snapshotted, final, filed, or superseded?
- What limitations, exclusions, warnings, or unsupported scenarios apply?

PXL follows the same enterprise ERP principles used by NetSuite, SAP Business One, Microsoft Dynamics, and Oracle Fusion:

- accounting context is always visible;
- filters are explicit and never hidden;
- numbers are traceable;
- reports reconcile where reconciliation is meaningful;
- exports are labeled and reproducible;
- audit and provenance are visible without polluting the primary report body;
- personalization changes presentation only, never accounting logic;
- server-side authorization and validated data sources govern report results;
- report pages use one shared visual and interaction system.

## 2. Relationship to transaction workspaces

Transaction pages are governed by `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md`.

Report pages are governed by this document.

The two standards must connect cleanly:

- report drilldown opens transaction workspaces for source documents;
- transaction workspaces drill back to originating reports where context is available;
- report links preserve report filters, mode, company, period, and currency;
- transaction links preserve document context and audit traceability;
- both standards use the same table density, status badge language, theme restraint, audit vocabulary, and source-of-truth discipline.

Reports must not duplicate full transaction workspaces. Transactions must not duplicate full reports. Each has a single responsibility.

## 3. Applies to

This standard applies to all reporting surfaces, including but not limited to:

- Accounting: General Ledger, Account Detail, Trial Balance, Balance Sheet, Income Statement, Cash Flow, Changes in Equity, Journal Register, Posting Review, Reversal Review, Control Account Reconciliation, Period Closing Reports.
- Sales and AR: Sales Register, Sales by Customer, Sales by Item, Sales by Branch, Customer Ledger, AR Aging, Collection Monitoring, Credit Memo Register, Debit Memo Register, Receipt Register, Customer Balance Summary.
- Purchasing and AP: Purchase Register, Purchases by Supplier, Purchases by Item, Supplier Ledger, AP Aging, Payment Voucher Register, Vendor Credit Register, Cash Disbursement Report, Supplier Balance Summary.
- Banking and Treasury: Bank Position, Cash Position, Bank Reconciliation, Outstanding Checks, Deposits in Transit, Cash Receipts Book, Cash Disbursements Book, Petty Cash Reports.
- Inventory: Stock Balance, Inventory Valuation, Inventory Movements, Stock Aging, Stock Reorder, Warehouse Balance, Inventory to GL Reconciliation, COGS Analysis.
- Fixed Assets: Asset Register, Depreciation Schedule, Asset Movement, Asset Disposal, Book versus Tax Depreciation, Fixed Asset to GL Reconciliation.
- Tax and Compliance: VAT Output, VAT Input, VAT Reconciliation, Percentage Tax, EWT, CWT, 2307, QAP, SAWT, SLSP, RELIEF, BIR Books, CAS Reports, Tax Working Papers, Filing and Submission Status.
- Audit and System: Audit Log, User Activity, Role and Permission Review, Posting Exceptions, Number Series Exceptions, Locked Period Activity, Data Import History, Report Export History, Report Snapshot History.
- Management: Branch P&L, Department Reports, Cost Center Reports, Gross Margin, Comparative Financial Statements, Audit Support Packages.

## 4. Standard report page structure

Every report page should eventually use this structure:

1. Report Header
2. Report Purpose or Description
3. Company, Branch, Period, and Currency Context
4. Filter Bar
5. View or Mode Selector
6. KPI or Summary Strip, only when useful
7. Reconciliation Status, where applicable
8. Report Table or Financial Statement Body
9. Drilldown and Drillback
10. Notes, Exceptions, and Warnings
11. Export, Print, and Snapshot Controls
12. Report Provenance and Audit Information

Do not force every report to display every section. The architecture is standard, but report-specific configuration determines which sections appear.

Required rule: if a section is omitted, the report specification must say whether it is not applicable, deferred, or intentionally hidden behind a collapsed panel.

## 5. Report header standard

### Purpose

The report header identifies the report and the accounting context currently being viewed. It must stay compact and should not become a dashboard.

### Standard header content

Display where applicable:

- Report Name
- Short Purpose
- Company
- Branch or Consolidation Scope
- Reporting Period
- As-of Date or Date Range
- Currency
- Accounting Basis
- Report Mode
- Data Status
- Last Refreshed
- Generated By, where relevant

### Standard header actions

Visible header actions should be limited and consistent:

- Refresh
- Apply Filters
- Reset Filters
- Save View
- Export
- Print
- Snapshot
- More Actions

The visible action row should stay compact. Lower-frequency actions belong in `More Actions`.

### Header information that must not be duplicated

Do not permanently display these in the header when they belong elsewhere:

- full filter details, which belong in applied filter chips or the filter panel;
- full SQL/RPC/source metadata, which belongs in Provenance;
- export history, which belongs in Audit or Report Export History;
- full reconciliation exception lists, which belong in Reconciliation or Exceptions;
- full drill paths, which belong in report links and documentation;
- technical identifiers, which belong in System or Provenance.

## 6. Report purpose standard

Every report must state its purpose in one concise sentence. The purpose should answer the business question.

Good examples:

- "Shows customer receivable balances by aging bucket as of the selected date."
- "Compares inventory subledger value against inventory control accounts."
- "Lists posted journal entries within the selected accounting period."

Avoid vague descriptions:

- "Displays data."
- "Shows report information."
- "Accounting report."

The purpose may appear under the report name or in a compact introductory panel.

## 7. Company, branch, period, and currency context

Report context must be visible before the user interprets any amount.

Standard context fields:

- Company
- Branch, entity, or consolidation scope
- Fiscal year
- Fiscal period
- Date range or as-of date
- Currency
- Accounting basis
- Posting basis
- Report mode
- Data status

No report may use an invisible default company, branch, period, posting state, or currency that changes results without being shown.

## 8. Filter bar standard

All reports should use one reusable filter system.

### Supported filter families

Use only filters that have accounting meaning for the report:

- Company
- Branch
- Department
- Cost Center
- Project
- Location
- Functional Entity
- Customer
- Supplier
- Item
- Account
- Account Range
- Document Type
- Status
- Tax Code
- ATC
- Fiscal Year
- Fiscal Period
- Date From
- Date To
- As-of Date
- Currency
- Posting State
- Include Zero Balances
- Include Reversed
- Include Unposted, only when explicitly supported
- Comparative Period
- Consolidated or Standalone
- Summary or Detail

### Required behavior

- Compact layout.
- Clear active-filter count.
- Applied-filter chips.
- Reset action.
- Saved filter views.
- User preference persistence where appropriate.
- No hidden default filters.
- Clear "not applicable" state when a filter does not apply to a report.
- Server-side validation of filter scope.
- Report result metadata must echo the applied filters.

### Filter ownership

The filter bar controls report presentation and query parameters. It does not define business rules. Accounting inclusion, exclusion, posting-state handling, currency basis, and reconciliation logic belong in governed report definitions, views, or RPCs.

## 9. Report modes

Report modes are named perspectives with documented accounting meaning. Do not create vague or overlapping modes.

Common modes:

- Summary
- Detail
- By Document
- By Account
- By Customer
- By Supplier
- By Branch
- By Department
- Comparative
- Monthly
- Quarterly
- Annual
- As-of
- Movement
- Balance
- Posted Only
- Exception Only

Every supported mode must document:

- purpose;
- grouping;
- date basis;
- posting-state basis;
- currency basis;
- totals behavior;
- drill path;
- reconciliation target, if any.

Mode selection must preserve current filters unless a filter is invalid for the selected mode. Invalidated filters must be shown to the user.

## 10. KPI or summary strip

Use a summary strip only when it improves interpretation. Do not duplicate totals already clearly visible in the report body.

Examples:

- AR Aging: Total AR, Current, 1-30, 31-60, 61-90, Over 90, Overdue percent.
- VAT: Output VAT, Input VAT, Net VAT Payable, GL Difference, Unreconciled Items.
- Trial Balance: Total Debit, Total Credit, Difference, Unmapped Accounts, Balance Status.
- Bank Reconciliation: Book Balance, Bank Statement Balance, Outstanding Checks, Deposits in Transit, Difference.

Summary strips must use the same accounting number formatting as the report body.

## 11. Reconciliation status standard

Every accounting or tax report with a control-account or source-ledger relationship must display reconciliation status.

### Reconciliation states

- Reconciled
- Reconciled with Warnings
- Not Reconciled
- Not Applicable
- Not Yet Validated

Do not show a green `Reconciled` label unless authoritative server-side validation was performed.

### Required reconciliation fields

Show where applicable:

- Report Amount
- GL Amount
- Difference
- Tolerance
- Last Validation Date
- Validation Method
- Drill to Exceptions

### Common reconciliation targets

- AR Aging = AR Control.
- AP Aging = AP Control.
- Inventory Valuation = Inventory GL.
- Fixed Asset Register = Fixed Asset GL.
- VAT Ledger = VAT GL Accounts.
- EWT Ledger = EWT Payable GL.
- Trial Balance Debit Total = Trial Balance Credit Total.
- Financial Statements = Trial Balance.
- 2307 and QAP = EWT Ledger.
- Bank Reconciliation = Bank Statement plus Book Ledger.

Reconciliation logic must be computed server-side or through approved governed report definitions. React may render results; it must not invent reconciliation truth from unrelated raw rows.

## 12. Report table standard

All tabular reports must use one reusable enterprise report table.

### Required capabilities

- Sticky headers.
- Frozen key columns.
- Right-aligned numeric columns.
- Accounting number formatting.
- Negative number formatting based on the selected accounting preference.
- Zero display preferences.
- Totals and subtotals.
- Grouping.
- Expand and collapse.
- Sorting.
- Filtering.
- Column chooser.
- Column resizing.
- Column reordering.
- Saved views.
- Compact density by default.
- Export.
- Pagination or virtualization.
- Keyboard navigation.
- Copy selection.
- Drillable links.
- Clear empty states.
- Loading skeletons.
- Error states.

Do not independently implement different table behavior for each report.

### Standard table behavior

- Text columns align left.
- Date columns align left or center consistently.
- Numeric and currency columns align right.
- Debit, credit, tax, balance, quantity, rate, and variance fields use stable formatting.
- Totals rows use stronger emphasis than detail rows but must not look decorative.
- Hover state is subtle and neutral.
- Clickable report links use one consistent link style.
- Sticky rows and columns must not obscure focus, keyboard navigation, or screen-reader labels.

## 13. Financial statement presentation

Financial statements must not look like ordinary data tables. They require structured statement presentation.

Required features where applicable:

- Account groups.
- Subgroups.
- Indentation.
- Subtotals.
- Grand totals.
- Comparative columns.
- Variance amount.
- Variance percent.
- Expand and collapse.
- Hide zero balances.
- Drill to Account Detail.
- Drill to General Ledger.
- Drill to Journal Entry.
- Drill to Source Document.

Supported statement modes may include:

- Current Period.
- Year to Date.
- Comparative Prior Period.
- Comparative Prior Year.
- Monthly Trend.
- Budget versus Actual, future.

Financial statement line definitions should be governed configuration, not arbitrary per-page layout code.

## 14. Drilldown and drillback standard

All applicable report pages must support this standard trace path:

```text
Report Summary
→ Report Detail
→ Account Detail
→ General Ledger
→ Journal Entry
→ Source Document
→ Source Line
→ Attachment / Evidence
```

The return path must also work:

```text
Source Document
→ Back to Journal Context
→ Back to GL / Detail Context
→ Back to Original Report State
```

### Requirements

- Amounts and document references are clickable when traceable.
- Original filters, report mode, sort, grouping, and scroll context are preserved.
- Browser Back works correctly.
- `Back to Report` returns to the same state.
- Deep links are supported.
- Open in new tab is supported where appropriate.
- No drilldown page should become a dead end.
- Drill links must be permission-aware.

The drill path for every report must be documented in the report specification and, where transaction relationships are involved, cross-referenced with `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`.

## 15. Report tabs or subsections

Use report tabs only when each tab has a distinct reporting purpose.

Common report tabs:

- Summary
- Detail
- Reconciliation
- Exceptions
- Related Documents
- Audit / Provenance
- Notes
- System

Do not use tabs to hide ordinary filters or create artificial dashboards. If a report can be expressed clearly as one structured body plus collapsible sections, avoid tabs.

## 16. Exceptions and warnings

Reports must expose data problems instead of silently excluding them.

Examples:

- Unmapped accounts.
- Missing tax codes.
- Missing ATC.
- Unposted transactions.
- Reversed transactions.
- Out-of-period postings.
- Cross-company mismatch.
- Orphaned journal lines.
- Missing source documents.
- Duplicate document numbers.
- Control-account differences.
- Tax-ledger differences.
- Invalid master data.
- Unsupported report scenarios.

Every exception or warning should show:

- count;
- severity;
- affected amount where relevant;
- source area;
- drill to detail where possible;
- whether the exception is included, excluded, or informational.

Do not create audit findings for cosmetic preferences. Create audit findings only for genuine accounting, tax, reconciliation, security, data-integrity, report-correctness, or production-readiness defects.

## 17. Export and print standard

Exports must be standardized across all reports.

Supported formats where applicable:

- Excel
- CSV
- PDF
- Print View
- BIR DAT or required compliance format

Every export should preserve:

- Report Name
- Company
- Branch
- Period
- Date Range or As-of Date
- Filters
- Currency
- Accounting Basis
- Report Mode
- Generated Date
- Generated By
- Page or Version
- Reconciliation Status
- Source or Snapshot ID where applicable

Never export an unlabeled data dump.

Export permissions must be enforced server-side. A hidden or disabled button is not a security control.

## 18. Report snapshots and reproducibility

For final, filed, submitted, audited, or compliance-sensitive reports, support immutable report snapshots where architecture requires it.

### Snapshot content

A report snapshot should record:

- Report Type
- Company
- Period
- Filters
- Data Source Version
- Generated By
- Generated At
- Row Count
- Totals
- Reconciliation Result
- Source Hash
- Output File Reference
- Superseded By
- Snapshot Status

### Snapshot states

Use clear state labels:

- Live
- Saved
- Snapshotted
- Final
- Filed
- Superseded
- Void or Withdrawn, where applicable

Live reports and snapshots must be visually distinct. Never present a live-changing report as historical filed evidence.

## 19. Audit and provenance

Every report should expose, where applicable:

- Data Source
- Source Views or RPCs
- Last Refresh
- Generated By
- Exported By
- Snapshot Version
- Applied Filters
- Report Mode
- Reconciliation Function
- Accounting Basis
- Currency Basis
- Included Statuses
- Excluded Statuses
- Report Definition Version

This information may live in an Audit / Provenance tab, compact expandable panel, or System subsection. It should not clutter the report body.

## 20. User personalization

Reports should support consistent user preferences:

- Saved Views
- Default Filters
- Visible Columns
- Column Order
- Column Widths
- Density
- Sort Order
- Grouping
- Expanded or Collapsed Groups
- Preferred Export Format
- Preferred Accounting Number Format

Personalization must never change accounting logic. A saved view may hide, show, order, group, or format columns, but it may not redefine inclusion rules, posting-state rules, tax logic, currency conversion, or reconciliation logic.

## 21. Permissions and data security

Every report must respect:

- Company membership.
- Branch access.
- Role permissions.
- Sensitive data restrictions.
- Payroll confidentiality.
- Tax-report access.
- Audit-log access.
- Export permissions.
- Snapshot permissions.

UI filtering is not a security boundary. Report data must remain protected server-side through RLS, validated RPCs, governed views, or another approved architecture.

Permission failures must be explicit:

- show a compact access-denied state;
- do not leak row counts, totals, customer names, employee names, or tax amounts;
- do not allow exports or snapshots of unauthorized data;
- do not use client-side filtering as a substitute for authorization.

## 22. Performance standard

Accounting reports must be computed by appropriate server-side mechanisms, not by loading large raw datasets into React.

### Expectations

Each report specification should define target behavior for:

- initial load;
- filter application;
- mode switching;
- drilldown;
- export;
- large datasets;
- financial statement generation;
- aging report generation;
- tax reconciliation;
- query cancellation.

### Approved patterns

- Server-side computation.
- Indexed views or optimized queries.
- RPCs for accounting logic.
- Pagination.
- Virtualization.
- Explicit refresh behavior.
- Safe caching only where source freshness rules allow it.
- Loading states and skeletons.
- Error states with retry.

Avoid:

- computing accounting balances from large raw client-side arrays;
- exporting from partial client-side pages without warning;
- blocking the browser during report calculation;
- silently truncating rows;
- hiding long-running query failures behind empty states.

## 23. Report-specific documentation standard

Every report must have a specification that records:

- Purpose
- Intended User
- Source Data
- Inclusion Rules
- Exclusion Rules
- Date Basis
- Posting Status Basis
- Currency Basis
- Grouping
- Totals
- Reconciliation Target
- Drilldown Path
- Drillback Path
- Export Formats
- Snapshot Requirement
- Permissions
- Known Limitations
- Test Scenarios
- Production Status

Report specifications may live in module documentation or in this standard's rollout matrix while the report is being adopted. Mature reports should have dedicated specs when the logic is material, regulated, or reconciliation-sensitive.

## 24. Reusable component inventory

Do not create page-specific equivalents when a shared component is appropriate.

Canonical reusable components:

- `ReportWorkspaceLayout`
- `ReportHeader`
- `ReportPurpose`
- `ReportContextBar`
- `ReportFilterBar`
- `AppliedFilterChips`
- `ReportModeSelector`
- `ReportSummaryStrip`
- `ReconciliationBanner`
- `EnterpriseReportTable`
- `FinancialStatementView`
- `ReportDrillLink`
- `ExceptionPanel`
- `ReportTabs`
- `ExportMenu`
- `PrintView`
- `SnapshotPanel`
- `ReportProvenancePanel`
- `SavedReportViews`
- `ReportEmptyState`
- `ReportLoadingState`
- `ReportErrorState`

Shared hooks and contracts should be created around report concerns:

- report context resolution;
- filter state and serialization;
- saved views;
- table preferences;
- query lifecycle;
- reconciliation result loading;
- drill link generation;
- export job tracking;
- snapshot metadata;
- permission evaluation.

## 25. UI and visual design standard

Reports must feel:

- trustworthy;
- accounting-first;
- structured;
- information-dense;
- calm;
- consistent;
- audit-ready;
- professional;
- desktop-first;
- reusable.

Use:

- sharp or minimally rounded sections;
- thin neutral borders;
- clear section headers;
- consistent table styling;
- restrained theme colors;
- professional number alignment;
- minimal wasted space;
- clear report context;
- compact empty states;
- precise section spacing.

Avoid:

- dashboard-like decorative cards where accounting context matters more;
- excessive gradients;
- oversized KPI tiles;
- unnecessary animations;
- unique visual systems per report;
- hidden report assumptions;
- bold text everywhere;
- unrelated icons as decoration.

### Typography

Use strong emphasis only for:

- report name;
- section titles;
- active mode or tab;
- totals;
- reconciliation status;
- exception severity.

All other labels and values should rely on spacing, alignment, and hierarchy rather than excessive bold weight.

### Status language

Use status colors only for state:

- green: success or reconciled;
- orange: warning;
- red: error or unreconciled;
- blue: informational;
- gray: neutral, inactive, not applicable, pending.

Do not use color as decoration.

### Empty states

Empty states must be concise and professional:

- "No transactions match the current filters."
- "No reconciliation exceptions found."
- "No snapshot has been created for this report."

Avoid oversized panels, debug wording, or vague text.

### Loading states

Show the report context and active filters while loading. Use skeletons or compact spinners for the report body. Do not clear the entire page unless context changed.

### Responsive behavior

Reports are desktop-first. On narrow screens:

- preserve accounting context;
- keep filters accessible;
- allow horizontal table scroll for wide reports;
- avoid hiding reconciliation status;
- do not collapse financial statements into ambiguous cards.

### Accessibility

Reports must support:

- keyboard navigation;
- visible focus states;
- text alternatives for status indicators;
- accessible table headers;
- screen-reader labels for drill links and actions;
- sufficient color contrast;
- non-color status indicators.

## 26. Extension rules for future reports

Future reports must extend this standard instead of creating custom layouts.

Rules:

1. Start from `ReportWorkspaceLayout`.
2. Define the report purpose.
3. Define authoritative source data.
4. Define allowed filters and report modes.
5. Define reconciliation target or mark `Not Applicable`.
6. Define drilldown and drillback paths.
7. Define export and snapshot requirements.
8. Define audit and provenance metadata.
9. Define permission rules.
10. Define performance strategy.
11. Define tests before marking the report production-ready.

Only add report-specific tabs, fields, or controls when the accounting purpose requires them.

## 27. Developer guidelines

### Naming conventions

Use consistent names:

- layout components: `ReportWorkspaceLayout`, `ReportHeader`, `ReportFilterBar`;
- report pages: `<ReportName>ReportPage`;
- report hooks: `use<ReportName>Report`;
- shared report hooks: `useReportFilters`, `useReportSavedViews`, `useReportExport`, `useReportSnapshot`;
- types: `<ReportName>Filters`, `<ReportName>Row`, `<ReportName>Summary`, `<ReportName>Reconciliation`;
- route IDs: stable, lowercase, report-specific paths.

### Suggested folder structure

```text
src/components/report/
  ReportWorkspaceLayout.tsx
  ReportHeader.tsx
  ReportFilterBar.tsx
  AppliedFilterChips.tsx
  ReportModeSelector.tsx
  ReportSummaryStrip.tsx
  ReconciliationBanner.tsx
  EnterpriseReportTable.tsx
  FinancialStatementView.tsx
  ReportTabs.tsx
  ExportMenu.tsx
  SnapshotPanel.tsx
  ReportProvenancePanel.tsx
  ReportStates.tsx

src/features/reports/
  shared/
    reportTypes.ts
    reportFilters.ts
    reportPreferences.ts
    reportDrillLinks.ts
    reportExport.ts
  accounting/
  sales-ar/
  purchasing-ap/
  banking/
  inventory/
  fixed-assets/
  tax-compliance/
  audit-system/
  management/
```

Use existing project structure where necessary, but do not fork shared report behavior into every page.

### Data-loading patterns

- Prefer governed views or RPCs for report logic.
- Query only the fields required by the report mode.
- Keep report result metadata with the rows.
- Return reconciliation metadata from the same governed report path or a clearly linked validation path.
- Include filter echo metadata in report responses.
- Include row count and truncation status when pagination or limits apply.
- Use explicit loading, error, stale, refreshed, and snapshot states.

### TypeScript contracts

Shared report interfaces should cover:

- report identity;
- context;
- filters;
- modes;
- columns;
- rows;
- summary metrics;
- reconciliation;
- exceptions;
- provenance;
- export metadata;
- snapshot metadata;
- permissions.

Do not use `any` for financial rows, reconciliation results, filter contracts, or export metadata.

### Permissions

- UI components may hide unauthorized actions for usability.
- Server-side report calls must enforce authorization.
- Export and snapshot endpoints must repeat authorization checks.
- Drill links must not expose unauthorized source document IDs.

### Testing expectations

Report tests should cover:

- filter serialization;
- date-basis correctness;
- posting-state inclusion;
- currency handling;
- totals;
- reconciliation;
- drill link generation;
- export metadata;
- permission denial;
- empty states;
- large-result behavior where applicable.

Accounting, tax, and compliance reports require data-level tests, not only visual tests.

## 28. Standard rollout matrix schema

The report rollout matrix must track these fields for every report:

- Report Name
- Module
- Canonical Route
- Current Status
- Source Data
- Standard Workspace Adoption
- Filters
- Modes
- Summary Metrics
- Reconciliation
- Drilldown
- Drillback
- Export
- Snapshot
- Audit / Provenance
- Permissions
- Performance Risk
- Missing Tests
- Remaining Gaps
- Recommended Priority

Until a report is audited against this standard, use explicit values such as `Assessment pending`, `Not started`, `Required`, `Not applicable`, or `TBD`. Do not mark a report compliant without evidence.

## 29. Current report rollout matrix

This matrix inventories current routed report pages and the work required to adopt the PXL Standard Report Workspace. `Assessment pending` means the route exists, but the page has not yet been certified against this standard.

| Report Name | Module | Canonical Route | Current Status | Source Data | Standard Workspace Adoption | Filters | Modes | Summary Metrics | Reconciliation | Drilldown | Drillback | Export | Snapshot | Audit / Provenance | Permissions | Performance Risk | Missing Tests | Remaining Gaps | Recommended Priority |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| General Ledger | Accounting | `/general-ledger` | Existing route, assessment pending | GL tables/views TBD | Not started | Required | Detail, by account, by document | Optional | GL self-balance and source linkage | Required to JE/source | Required | Required | Optional | Required | Required | High | TBD | Adopt report workspace and validate drill path | P0 |
| Account Detail Ledger | Accounting | `/account-detail-ledger` | Existing route, assessment pending | GL account detail TBD | Not started | Required | Detail, movement, balance | Optional | Account balance to GL | Required to JE/source | Required | Required | Optional | Required | Required | High | TBD | Standard table and provenance | P0 |
| Trial Balance | Accounting | `/trial-balance` | Existing route, assessment pending | GL balances TBD | Not started | Required | Summary, detail, comparative | Required | Total debits equal credits | Required to account detail | Required | Required | Snapshot recommended | Required | Required | High | TBD | Recommended pilot candidate | P0 |
| Balance Sheet | Accounting | `/balance-sheet` | Existing route, assessment pending | Financial statement definitions TBD | Not started | Required | Current, YTD, comparative | Required | To trial balance | Required to account detail | Required | Required | Snapshot recommended | Required | Required | High | TBD | Statement presentation and line definitions | P0 |
| Income Statement | Accounting | `/income-statement` | Existing route, assessment pending | Financial statement definitions TBD | Not started | Required | Period, YTD, comparative | Required | To trial balance | Required to account detail | Required | Required | Snapshot recommended | Required | Required | High | TBD | Statement presentation and line definitions | P0 |
| Statement of Cash Flows | Accounting | `/statement-of-cash-flows` | Existing route, assessment pending | Cash flow definitions TBD | Not started | Required | Direct or indirect TBD, comparative | Required | To GL and cash accounts | Required to account detail | Required | Required | Snapshot recommended | Required | Required | High | TBD | Statement rules and reconciliation | P1 |
| Statement of Changes in Equity | Accounting | `/statement-of-changes-in-equity` | Existing route, assessment pending | Equity movement definitions TBD | Not started | Required | Period, comparative | Required | To equity accounts | Required to account detail | Required | Required | Snapshot recommended | Required | Required | Medium | TBD | Statement rules and reconciliation | P1 |
| Comparative Financial Statements | Management | `/comparative-financial-statements` | Existing route, assessment pending | Financial statement definitions TBD | Not started | Required | Period, prior period, prior year | Required | To trial balance | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Comparative mode standardization | P1 |
| Journal Register | Accounting | `/posting-review` | Existing route, assessment pending | Journal/posting tables TBD | Not started | Required | Register, exception | Optional | To GL posting totals | Required to JE/source | Required | Required | Optional | Required | Required | Medium | TBD | Clarify route/report name and standard table | P0 |
| Reversal Review | Accounting | `/reversal-review` | Existing route, assessment pending | Journal reversal tables TBD | Not started | Required | Detail, exception | Optional | To reversal journals | Required to JE/source | Required | Required | Optional | Required | Required | Medium | TBD | Exception and drillback standard | P1 |
| Control Account Reconciliation | Accounting | `/control-account-recon` | Existing route, assessment pending | Control/subledger reconciliation TBD | Not started | Required | By control account, exception | Required | Required by definition | Required to exceptions | Required | Required | Snapshot recommended | Required | Required | High | TBD | Recommended reconciliation pattern source | P0 |
| Period Closing Reports | Accounting | `/period-closing` | Existing route, assessment pending | Period close tables TBD | Not started | Required | Checklist, exception, period | Required | Close readiness and GL status | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Align close controls with report standard | P0 |
| Accounting Trace | Accounting | `/accounting-trace` | Existing route, assessment pending | Trace views TBD | Not started | Required | Source to GL, GL to source | Optional | Not applicable | Required | Required | Optional | Optional | Required | Required | Medium | TBD | Standardize as drill/provenance report | P1 |
| Accounting Source | Accounting | `/accounting-source` | Existing route, assessment pending | Source document views TBD | Not started | Required | By source, by journal | Optional | To source and GL | Required | Required | Optional | Optional | Required | Required | Medium | TBD | Standardize drillback contract | P1 |
| Amortization Schedules | Accounting | `/amortization-schedules` | Existing route, assessment pending | Amortization schedules TBD | Not started | Required | Schedule, movement | Optional | To GL deferral accounts | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standard table and reconciliation | P2 |
| Revenue Recognition Schedules | Accounting | `/revenue-recognition-schedules` | Existing route, assessment pending | Revenue schedules TBD | Not started | Required | Schedule, movement | Optional | To revenue/deferred revenue GL | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standard table and recognition provenance | P2 |
| Sales Register | Sales/AR | `/sales-registers` | Existing route, assessment pending | Sales documents and tax ledger TBD | Not started | Required | Register, by customer, by item | Optional | To sales GL and VAT output | Required to invoice | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Adopt standard report table | P1 |
| Sales Tax Review | Sales/AR | `/sales-tax-review` | Existing route, assessment pending | Sales tax detail TBD | Not started | Required | Detail, exception | Required | To VAT output ledger | Required to source document | Required | Required | Snapshot recommended | Required | Required | High | TBD | Align to tax reconciliation pattern | P0 |
| AR Aging | Sales/AR | `/ar-aging` | Existing route, assessment pending | AR ledger and customer balances TBD | Not started | Required | Summary, detail, by customer | Required | AR Aging to AR Control | Required to customer ledger/invoice | Required | Required | Snapshot recommended | Required | Required | High | TBD | Recommended pilot candidate | P0 |
| Collection Monitoring | Sales/AR | `/collection-monitoring` | Existing route, assessment pending | Receipts/collections TBD | Not started | Required | Summary, detail, by customer | Required | To cash and AR clearing where applicable | Required to receipt/invoice | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standardize collection metrics and trace | P1 |
| EWT Working Papers | Sales/AR | `/ewt-working-papers` | Existing route, assessment pending | Withholding/tax ledger TBD | Not started | Required | Summary, detail, exception | Required | To EWT/CWT ledger | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Align with withholding report standard | P0 |
| 2307 Received Review | Sales/AR | `/2307-received-review` | Existing route, assessment pending | 2307 received records TBD | Not started | Required | Detail, exception | Required | To CWT receivable ledger | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Compliance provenance and exports | P0 |
| Percentage Tax Review | Sales/AR | `/pt-review` | Existing route, assessment pending | PT taxable sales TBD | Not started | Required | Summary, detail, exception | Required | To PT ledger/GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Tax reconciliation and snapshot | P0 |
| Summary List of Sales | Sales/AR | `/sls` | Existing route, assessment pending | Sales/customer tax data TBD | Not started | Required | BIR list, detail | Required | To VAT/sales ledgers | Required | Required | Required | Required for filing | Required | Required | High | TBD | BIR export/snapshot standard | P0 |
| Purchase Register | Purchasing/AP | `/purchase-registers` | Existing route, assessment pending | Purchase documents and tax ledger TBD | Not started | Required | Register, by supplier, by item | Optional | To purchases/AP/VAT input | Required to source document | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Adopt standard report table | P1 |
| Input VAT Review | Purchasing/AP | `/input-vat-review` | Existing route, assessment pending | Input VAT details TBD | Not started | Required | Detail, exception | Required | To VAT input ledger | Required to source document | Required | Required | Snapshot recommended | Required | Required | High | TBD | Align to tax reconciliation pattern | P0 |
| AP Aging | Purchasing/AP | `/ap-aging` | Existing route, assessment pending | AP ledger and supplier balances TBD | Not started | Required | Summary, detail, by supplier | Required | AP Aging to AP Control | Required to supplier ledger/bill | Required | Required | Snapshot recommended | Required | Required | High | TBD | Subsidiary/control reconciliation | P0 |
| Payment Monitoring | Purchasing/AP | `/payment-monitoring` | Existing route, assessment pending | Payments/disbursements TBD | Not started | Required | Summary, detail, by supplier | Required | To cash and AP clearing where applicable | Required to payment/bill | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standardize payment trace | P1 |
| EWT Summary | Purchasing/AP | `/ewt-summary` | Existing route, assessment pending | EWT payable ledger TBD | Not started | Required | Summary, detail, by ATC | Required | To EWT payable GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Withholding reconciliation | P0 |
| 2307 Issued Review | Purchasing/AP | `/2307-issued-review` | Existing route, assessment pending | 2307 issued records TBD | Not started | Required | Detail, exception | Required | To EWT payable ledger | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Certificate/audit provenance | P0 |
| Bank Reconciliation | Banking | `/bank-reconciliation` | Existing route, assessment pending | Bank ledger and statement data TBD | Not started | Required | Reconciliation, exception | Required | Book to bank statement | Required to transactions | Required | Required | Snapshot recommended | Required | Required | High | TBD | Reconciliation and exceptions standard | P0 |
| Outstanding Checks | Banking | `/outstanding-checks` | Existing route, assessment pending | Bank checks/payment data TBD | Not started | Required | Detail, aging | Required | To bank reconciliation | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standard table and bank context | P1 |
| Deposits in Transit | Banking | `/deposits-in-transit` | Existing route, assessment pending | Receipts/deposit data TBD | Not started | Required | Detail, aging | Required | To bank reconciliation | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standard table and bank context | P1 |
| Bank Position | Banking | `/reports-bank-position` | Existing route, assessment pending | Bank accounts and ledgers TBD | Not started | Required | Summary, detail, as-of | Required | To bank GL balances | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Cash/bank context and provenance | P1 |
| Cash Count Sheet | Banking | `/cash-count-sheet` | Existing route, assessment pending | Cash count records TBD | Not started | Required | Count, variance | Required | To cash account where applicable | Required | Required | Required | Snapshot recommended | Required | Required | Medium | TBD | Evidence/snapshot controls | P1 |
| Check Register | Banking | `/reports-check-register` | Existing route, assessment pending | Check/payment data TBD | Not started | Required | Register, status | Optional | To bank ledger | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Standard table and export labels | P1 |
| Stock Balance | Inventory | `/stock-balance` | Existing route, assessment pending | Inventory balances TBD | Not started | Required | As-of, by item, by warehouse | Required | To inventory subledger | Required | Required | Required | Snapshot optional | Required | Required | High | TBD | Inventory report workspace adoption | P1 |
| Inventory Movements | Inventory | `/inventory-movements` | Existing route, assessment pending | Inventory movement ledger TBD | Not started | Required | Movement, by item, by warehouse | Optional | To inventory ledger | Required | Required | Required | Snapshot optional | Required | Required | High | TBD | Drill to source movement/document | P1 |
| Inventory Valuation | Inventory | `/inventory-valuation` | Existing route, assessment pending | Inventory valuation ledger TBD | Not started | Required | As-of, movement, by warehouse | Required | Inventory Valuation to Inventory GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Control reconciliation and costing provenance | P0 |
| Inventory Dashboard | Inventory | `/inventory-dashboard` | Existing route, assessment pending | Inventory KPIs TBD | Not started | Required | Summary | Optional | Not applicable or TBD | Required where KPI traceable | Required | Optional | Optional | Required | Required | Medium | TBD | Convert dashboard elements to report standard where used as report | P2 |
| Slow Moving Inventory | Inventory | `/reports-slow-moving-inventory` | Existing route, assessment pending | Inventory aging/movement TBD | Not started | Required | Aging, exception | Required | To stock balances where applicable | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Aging rules and thresholds | P1 |
| Fixed Asset Dashboard | Fixed Assets | `/fixed-asset-dashboard` | Existing route, assessment pending | Fixed asset KPIs TBD | Not started | Required | Summary | Optional | Not applicable or TBD | Required where KPI traceable | Required | Optional | Optional | Required | Required | Medium | TBD | Align dashboard/report boundary | P2 |
| Asset Register | Fixed Assets | `/asset-register` | Existing route, assessment pending | Fixed asset register TBD | Not started | Required | Register, by class, by branch | Required | Fixed Assets to GL | Required to asset/source | Required | Required | Snapshot recommended | Required | Required | High | TBD | Asset/GL reconciliation | P0 |
| Depreciation Schedule | Fixed Assets | `/reports-depreciation-schedule` | Existing route, assessment pending | Depreciation schedules TBD | Not started | Required | Book, tax, period | Required | Depreciation to GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Book/tax basis and trace | P0 |
| Book vs Tax Depreciation | Fixed Assets | `/reports-book-vs-tax-depreciation` | Existing route, assessment pending | Depreciation book/tax data TBD | Not started | Required | Comparative, exception | Required | To asset and tax schedules | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Difference explanations and provenance | P1 |
| Asset Disposal | Fixed Assets | `/reports-asset-disposal` | Existing route, assessment pending | Disposal records TBD | Not started | Required | Register, gain/loss | Required | To disposal GL entries | Required | Required | Required | Snapshot recommended | Required | Required | Medium | TBD | Disposal trace and attachments | P1 |
| VAT Dashboard | Tax/Compliance | `/vat-dashboard` | Existing route, assessment pending | VAT KPIs TBD | Not started | Required | Summary | Required | To VAT ledgers | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Align dashboard to tax report standard | P0 |
| VAT Working Papers | Tax/Compliance | `/vat-working-papers` | Existing route, assessment pending | VAT ledger/workpaper data TBD | Not started | Required | Summary, detail, exception | Required | To VAT GL accounts | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Recommended pilot candidate | P0 |
| VAT Output Summary | Tax/Compliance | `/vat-output-summary` | Existing route, assessment pending | Output VAT ledger TBD | Not started | Required | Summary, detail | Required | To output VAT GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Tax ledger reconciliation | P0 |
| VAT Input Summary | Tax/Compliance | `/vat-input-summary` | Existing route, assessment pending | Input VAT ledger TBD | Not started | Required | Summary, detail | Required | To input VAT GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Tax ledger reconciliation | P0 |
| VAT Reconciliation | Tax/Compliance | `/vat-reconciliation` | Existing route, assessment pending | VAT ledger and GL TBD | Not started | Required | Reconciliation, exception | Required | VAT ledger to GL | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Recommended pilot candidate | P0 |
| VAT Return 2550M | Tax/Compliance | `/vat-return-2550m` | Existing route, assessment pending | VAT return data TBD | Not started | Required | Return, working paper | Required | To VAT working papers | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and export provenance | P0 |
| VAT Return 2550Q | Tax/Compliance | `/vat-return-2550q` | Existing route, assessment pending | VAT return data TBD | Not started | Required | Return, working paper | Required | To VAT working papers | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and export provenance | P0 |
| VAT SLP | Tax/Compliance | `/vat-slp` | Existing route, assessment pending | VAT purchase list TBD | Not started | Required | List, detail | Required | To VAT input | Required | Required | Required | Snapshot required | Required | Required | High | TBD | BIR list/export standard | P0 |
| VAT SLSP Export | Tax/Compliance | `/vat-slsp-export` | Existing route, assessment pending | SLSP export data TBD | Not started | Required | Export, validation | Required | To SLSP source reports | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Export byte provenance | P0 |
| VAT RELIEF Export | Tax/Compliance | `/vat-relief-export` | Existing route, assessment pending | RELIEF export data TBD | Not started | Required | Export, validation | Required | To VAT source reports | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Export byte provenance | P0 |
| Percentage Tax Dashboard | Tax/Compliance | `/pt-dashboard` | Existing route, assessment pending | PT KPIs TBD | Not started | Required | Summary | Required | To PT ledger/GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Tax report standard adoption | P0 |
| Percentage Tax Working Papers | Tax/Compliance | `/pt-working-papers` | Existing route, assessment pending | PT workpaper data TBD | Not started | Required | Summary, detail, exception | Required | To PT GL | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Working paper standard | P0 |
| Percentage Tax Return 2551Q | Tax/Compliance | `/pt-return-2551q` | Existing route, assessment pending | PT return data TBD | Not started | Required | Return, working paper | Required | To PT working papers | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P0 |
| Percentage Tax Reconciliation | Tax/Compliance | `/pt-reconciliation` | Existing route, assessment pending | PT ledger and GL TBD | Not started | Required | Reconciliation, exception | Required | PT ledger to GL | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Reconciliation standard | P0 |
| Percentage Tax Summary Register | Tax/Compliance | `/pt-summary-register` | Existing route, assessment pending | PT register data TBD | Not started | Required | Summary, detail | Required | To PT ledger | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Standard table and export | P0 |
| Withholding Tax Dashboard | Tax/Compliance | `/wt-dashboard` | Existing route, assessment pending | WT KPIs TBD | Not started | Required | Summary | Required | To withholding ledgers | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Tax report standard adoption | P0 |
| EWT Receivable Summary | Tax/Compliance | `/wt-ewt-receivable-summary` | Existing route, assessment pending | CWT/EWT receivable ledger TBD | Not started | Required | Summary, detail, by ATC | Required | To CWT receivable GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Withholding reconciliation | P0 |
| Withholding ATC Summary | Tax/Compliance | `/wt-atc-summary` | Existing route, assessment pending | WT ledger by ATC TBD | Not started | Required | By ATC, detail | Required | To withholding ledgers | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | ATC/versioning correctness | P0 |
| 1601EQ Working Papers | Tax/Compliance | `/wt-1601eq-working-papers` | Existing route, assessment pending | EWT payable workpapers TBD | Not started | Required | Summary, detail, exception | Required | To EWT payable GL | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Working paper and filing path | P0 |
| 1601EQ Return | Tax/Compliance | `/wt-1601eq-return` | Existing route, assessment pending | 1601EQ return data TBD | Not started | Required | Return, validation | Required | To 1601EQ working papers | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P0 |
| QAP | Tax/Compliance | `/wt-qap` | Existing route, assessment pending | QAP detail TBD | Not started | Required | BIR list, detail | Required | To EWT ledger | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Export/filed evidence | P0 |
| SAWT | Tax/Compliance | `/wt-sawt` | Existing route, assessment pending | SAWT detail TBD | Not started | Required | BIR list, detail | Required | To CWT/EWT received ledger | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Export/filed evidence | P0 |
| 2306 Certificates | Tax/Compliance | `/wt-2306-certificates` | Existing route, assessment pending | Certificate records TBD | Not started | Required | Register, certificate | Required | To FWT/EWT records | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Certificate provenance | P1 |
| FWT Working Papers | Tax/Compliance | `/wt-fwt-working-papers` | Existing route, assessment pending | FWT workpapers TBD | Not started | Required | Summary, detail | Required | To FWT GL | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Working paper standard | P1 |
| 1601FQ Working Papers | Tax/Compliance | `/wt-1601fq-working-papers` | Existing route, assessment pending | FQ workpapers TBD | Not started | Required | Summary, detail | Required | To FWT working papers | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Working paper standard | P1 |
| 1601FQ Return | Tax/Compliance | `/wt-1601fq-return` | Existing route, assessment pending | FQ return data TBD | Not started | Required | Return, validation | Required | To 1601FQ working papers | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P1 |
| Income Tax Dashboard | Tax/Compliance | `/inc-tax-dashboard` | Existing route, assessment pending | Income tax KPIs TBD | Not started | Required | Summary | Required | To income tax workpapers | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Dashboard/report boundary | P1 |
| Income Tax Computation | Tax/Compliance | `/inc-tax-computation` | Existing route, assessment pending | Income tax computation TBD | Not started | Required | Computation, detail | Required | To GL and tax adjustments | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Computation provenance | P1 |
| Book to Tax Reconciliation | Tax/Compliance | `/inc-tax-book-to-tax-recon` | Existing route, assessment pending | Book/tax adjustments TBD | Not started | Required | Reconciliation, exception | Required | Book income to taxable income | Required | Required | Required | Snapshot required when filed | Required | Required | High | TBD | Reconciliation standard | P1 |
| OSD | Tax/Compliance | `/inc-tax-osd` | Existing route, assessment pending | OSD computation TBD | Not started | Required | Computation | Required | To income tax computation | Required | Required | Required | Snapshot required when filed | Required | Required | Medium | TBD | Tax basis and limitation notes | P2 |
| NOLCO | Tax/Compliance | `/inc-tax-nolco` | Existing route, assessment pending | NOLCO schedules TBD | Not started | Required | Schedule, movement | Required | To income tax computation | Required | Required | Required | Snapshot required when filed | Required | Required | Medium | TBD | Schedule trace and expiration logic | P2 |
| Income Tax Credits | Tax/Compliance | `/inc-tax-credits` | Existing route, assessment pending | Tax credit schedules TBD | Not started | Required | Schedule, movement | Required | To income tax computation | Required | Required | Required | Snapshot required when filed | Required | Required | Medium | TBD | Credit trace and evidence | P2 |
| 1701Q | Tax/Compliance | `/inc-tax-1701q` | Existing route, assessment pending | Income tax return data TBD | Not started | Required | Return, validation | Required | To income tax computation | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P1 |
| 1701 | Tax/Compliance | `/inc-tax-1701` | Existing route, assessment pending | Income tax return data TBD | Not started | Required | Return, validation | Required | To income tax computation | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P1 |
| 1702Q | Tax/Compliance | `/inc-tax-1702q` | Existing route, assessment pending | Income tax return data TBD | Not started | Required | Return, validation | Required | To income tax computation | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P1 |
| 1702RT | Tax/Compliance | `/inc-tax-1702rt` | Existing route, assessment pending | Income tax return data TBD | Not started | Required | Return, validation | Required | To income tax computation | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Filing snapshot and provenance | P1 |
| MCIT | Tax/Compliance | `/inc-tax-mcit` | Existing route, assessment pending | MCIT computation TBD | Not started | Required | Computation, schedule | Required | To income tax computation | Required | Required | Required | Snapshot required when filed | Required | Required | Medium | TBD | Computation trace and limitations | P2 |
| Books Dashboard | Books/CAS | `/books-dashboard` | Existing route, assessment pending | Statutory books TBD | Not started | Required | Summary | Required | To statutory books | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Align book summaries with CAS evidence | P0 |
| General Journal Book | Books/CAS | `/books-general-journal` | Existing route, assessment pending | Journal book entries TBD | Not started | Required | Book, detail | Required | To GL/journals | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| Cash Receipts Book | Books/CAS | `/books-cash-receipts` | Existing route, assessment pending | Cash receipt book TBD | Not started | Required | Book, detail | Required | To receipts/cash GL | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| Cash Disbursements Book | Books/CAS | `/books-cash-disbursements` | Existing route, assessment pending | Cash disbursement book TBD | Not started | Required | Book, detail | Required | To payments/cash GL | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| Sales Journal Book | Books/CAS | `/books-sales-journal` | Existing route, assessment pending | Sales book TBD | Not started | Required | Book, detail | Required | To sales documents/GL | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| Cash Sales Journal Book | Books/CAS | `/books-cash-sales-journal` | Existing route, assessment pending | Cash sales book TBD | Not started | Required | Book, detail | Required | To sales/receipt GL | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| Purchase Journal Book | Books/CAS | `/books-purchase-journal` | Existing route, assessment pending | Purchase book TBD | Not started | Required | Book, detail | Required | To purchase/AP GL | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| Cash Purchases Journal Book | Books/CAS | `/books-cash-purchases-journal` | Existing route, assessment pending | Cash purchases book TBD | Not started | Required | Book, detail | Required | To purchases/payment GL | Required | Required | Required | Snapshot required where filed | Required | Required | High | TBD | Book/export provenance | P0 |
| CAS Dashboard | Books/CAS | `/cas-dashboard` | Existing route, assessment pending | CAS control data TBD | Not started | Required | Summary, exception | Required | To CAS evidence logs | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | CAS dashboard/report alignment | P0 |
| CAS Transaction Audit Log | Audit/System | `/cas-transaction-audit-log` | Existing route, assessment pending | CAS transaction log TBD | Not started | Required | Log, exception | Optional | To transaction audit evidence | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Provenance and immutable evidence | P0 |
| CAS Master Data Change Log | Audit/System | `/cas-master-data-change-log` | Existing route, assessment pending | Master data audit log TBD | Not started | Required | Log, by entity | Optional | To audit trail | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Permission and evidence standard | P0 |
| CAS System Parameter Logs | Audit/System | `/cas-system-parameter-logs` | Existing route, assessment pending | System parameter logs TBD | Not started | Required | Log, exception | Optional | To system audit trail | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Permission and provenance | P0 |
| CAS User Activity Log | Audit/System | `/cas-user-activity-log` | Existing route, assessment pending | User activity logs TBD | Not started | Required | Log, by user | Optional | To audit trail | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Sensitive access controls | P0 |
| CAS Attachment Register | Audit/System | `/cas-attachment-register` | Existing route, assessment pending | Attachment records TBD | Not started | Required | Register, by source | Optional | To source evidence | Required | Required | Required | Snapshot recommended | Required | Required | Medium | TBD | Attachment drill and provenance | P1 |
| CAS Document Void Register | Audit/System | `/cas-document-void-register` | Existing route, assessment pending | Void evidence tables TBD | Not started | Required | Register, exception | Required | To void evidence and journals | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Ensure immutable evidence fields display | P0 |
| CAS ATP Usage Log | Audit/System | `/cas-atp-usage-log` | Existing route, assessment pending | ATP usage evidence TBD | Not started | Required | Usage, exception | Required | To number series evidence | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | ATP range/provenance standard | P0 |
| CAS DAT File Generation | Audit/System | `/cas-dat-file-generation` | Existing route, assessment pending | DAT generation records TBD | Not started | Required | Generation, validation | Required | To statutory books and exports | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Export byte provenance and validation | P0 |
| CAS Audit Report | Audit/System | `/cas-audit-report` | Existing route, assessment pending | CAS audit package TBD | Not started | Required | Summary, exception, evidence | Required | To CAS logs/books | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Audit support package standard | P0 |
| CAS Export History | Audit/System | `/cas-export-history` | Existing route, assessment pending | Export history TBD | Not started | Required | Register, by report | Optional | To export evidence | Required | Required | Required | Snapshot recommended | Required | Required | Medium | TBD | Standard export metadata | P1 |
| Report Snapshot History | Audit/System | `/report-snapshots` | Existing route, assessment pending | Report snapshot records TBD | Not started | Required | Register, by report/status | Optional | To snapshot evidence | Required | Required | Required | Not applicable | Required | Required | Medium | TBD | Snapshot lifecycle and provenance | P1 |
| FWT Summary | Management/Tax | `/reports-fwt-summary` | Existing route, assessment pending | FWT ledger TBD | Not started | Required | Summary, detail | Required | To FWT GL | Required | Required | Required | Snapshot recommended | Required | Required | High | TBD | Withholding report alignment | P1 |
| Branch P&L | Management | `/reports-branch-pnl` | Existing route, assessment pending | GL by branch TBD | Not started | Required | Branch, comparative | Required | To trial balance/GL | Required | Required | Required | Snapshot optional | Required | Required | High | TBD | Statement presentation by branch | P1 |
| Department Report | Management | `/reports-department` | Existing route, assessment pending | GL by department TBD | Not started | Required | Department, comparative | Required | To trial balance/GL | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Segment reporting standard | P1 |
| Cost Center Report | Management | `/reports-cost-center` | Existing route, assessment pending | GL by cost center TBD | Not started | Required | Cost center, comparative | Required | To trial balance/GL | Required | Required | Required | Snapshot optional | Required | Required | Medium | TBD | Segment reporting standard | P1 |
| Gross Margin Report | Management | `/reports-gross-margin` | Existing route, assessment pending | Sales/COGS data TBD | Not started | Required | By item, customer, branch | Required | To sales and COGS GL | Required | Required | Required | Snapshot optional | Required | Required | High | TBD | Sales/COGS reconciliation | P1 |
| Audit Support Package | Management/Audit | `/reports-audit-support-package` | Existing route, assessment pending | Cross-module audit package TBD | Not started | Required | Package, evidence | Required | To selected source reports | Required | Required | Required | Snapshot required | Required | Required | High | TBD | Package manifest and reproducibility | P0 |

## 30. Pilot and implementation policy

Do not rebuild every report immediately.

Required sequence:

1. Define the standard.
2. Inventory existing reports.
3. Identify shared components.
4. Select one pilot report.
5. Implement the pilot.
6. Validate accounting, reconciliation, drilldown, export, and UX.
7. Freeze the reusable pattern.
8. Roll out module by module.

Recommended pilot candidates:

- Trial Balance, for financial reporting.
- AR Aging, for subsidiary/control reconciliation.
- VAT Reconciliation, for tax reporting.

Choose the pilot based on production priority and dependency, not visual simplicity.

## 31. Success criteria

The reporting platform is successful when:

- every report clearly states its purpose and context;
- filters are consistent and explicit;
- report modes have documented accounting meaning;
- tables are consistent;
- financial statements use statement presentation rather than ordinary grids;
- amounts are traceable;
- reports reconcile to authoritative ledgers where applicable;
- users can drill to source documents and source evidence;
- users can return without losing report context;
- exports are labeled and reproducible;
- final reports can be snapshotted where necessary;
- permissions are enforced server-side;
- audit and provenance are visible;
- report-specific limitations are stated;
- reports feel like one coherent PXL reporting system rather than unrelated pages.

## 32. UX decision log

These decisions govern future report work:

- Reports must not be simple tables with Export buttons. The standard requires purpose, context, filters, reconciliation, traceability, export metadata, and provenance.
- Hidden defaults are not allowed. Company, period, branch, currency, accounting basis, posting state, and mode must be visible when they affect results.
- A green reconciliation status requires authoritative validation. UI-only reconciliation indicators are prohibited.
- Personalization is allowed for presentation only. Saved views must never redefine accounting logic.
- Financial statements require statement-specific presentation. They must not be rendered as generic data grids.
- Export output must be labeled. Unlabeled CSV/Excel dumps are not acceptable for ERP reporting.
- Live reports and snapshots must be distinct. Filed or audit-sensitive evidence must not depend on changing live queries.
- Drilldown must include drillback. Source-document navigation is incomplete if users lose report context.
- Exceptions must be visible. Reports must not silently hide problematic accounting or tax data.
- Shared report components are mandatory. Per-report table/filter/export implementations create inconsistency and should be replaced during adoption.
