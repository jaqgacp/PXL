# PXL Transaction Workspace Standard

**Status:** Sole authoritative transaction-workspace UI architecture
**Authority:** Tier 1
**Version:** 2.1
**Effective:** 2026-07-18
**Implementation anchors:** `src/components/document/TransactionWorkspace.tsx`, `src/components/document/DocumentLayout.tsx`, `src/components/document/TransactionPrimitives.tsx`, `src/index.css`
**Business variation:** `PXL_TRANSACTION_WORKSPACE_PATTERNS.md`

This is the only authority for how a PXL transaction form or document view looks and behaves as a workspace. Sales Invoice, Vendor Bill, Purchase Order, Journal Entry, payments, inventory movements, banking documents, fixed-asset transactions, and future compliance transactions compose this architecture; none is a visual reference for another.

Accounting, tax, inventory, approval, lifecycle, permission, source-document, and field-source truth remain governed by their domain standards. Shared UI code must display that truth and must never become a posting or tax engine.

## 1. Invariants

Every applicable transaction uses the same ordered architecture:

1. page header;
2. workflow strip;
3. three-card information band;
4. one-line standard tab bar;
5. active tab and right sidebar in one content grid;
6. compact footer metadata when useful.

The following never vary by module: page grid, spacing, typography, card construction, border/radius/shadow, workflow component, tab component and order, sidebar architecture, button dimensions, table density, status presentation, empty/loading/error states, responsive rules, sticky rules, focus behavior, and theme behavior.

Only source-backed business content varies. `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` defines the permitted variation.

## 2. Workspace ownership

- `TransactionWorkspace` owns the fixed architecture and fixed tab contract.
- `DocumentLayout` owns the page grid, shared header, workflow placement, tab controller, content/sidebar grid, and footer.
- `TransactionPrimitives` owns information cards, facts, impact tables, links, and standard states.
- Domain pages own data fetching, draft state, business fields, calculations, lifecycle actions, permissions, and source-backed tab content.
- `LegacyTransactionWorkspace` is a compatibility composition only. It mounts the existing domain form once inside Lines and may not create another page shell.
- Page modules must not introduce a second header, second tab system, alternate sidebar width, page-specific workspace CSS, or company-controlled layout theme.

## 3. Fluid desktop layout

Transaction workspaces use the available application viewport. They are not narrow centered documents.

| Property | Standard |
| --- | --- |
| Workspace width | `100%` of the AppShell content viewport |
| Maximum width | None for transaction routes |
| Outer padding | 8px |
| Vertical section gap | 8px |
| Information band | Three equal columns from 1024px |
| Content grid | Fluid main column plus 240px sidebar from 1024px; 256px on larger desktops |
| Main content height | Natural content height; no arbitrary fixed or minimum panel height |
| Large monitors | Additional width goes to the main content/table, not outer margins |

The global AppShell reading-width cap may remain for setup and report pages, but a descendant transaction workspace removes that cap.

## 4. Responsive and zoom behavior

Supported desktop validation covers 1366px, 1440px, 1600px, and 1920px viewports at 90%, 100%, 110%, and 125% zoom.

- Header regions may wrap vertically without reordering their meaning.
- The three information cards stack below 1024px.
- The sidebar moves below the active tab only below 1024px; it never overlays the tab content.
- All fourteen tabs remain on one row at supported desktop widths. Labels may truncate with a native title; the bar may not require horizontal scrolling.
- Tables own horizontal overflow inside their panel. The page itself must not overflow horizontally.
- Browser zoom must not create a centered box, excessive outer margins, clipped actions, missing tabs, or disappearing modules.
- Dialogs, popovers, and lookup overlays render outside clipping containers and remain inside the viewport.

## 5. Sticky and scrolling rules

- AppShell navigation remains the highest persistent application region.
- The transaction header is sticky at the AppShell offset on desktop and becomes non-sticky below 1024px.
- The sidebar is independently sticky on desktop, with a viewport-bounded scroll area when its source-backed content is long.
- Table headers may be sticky inside their own scroll container.
- Tabs are not independently sticky because they must not collide with a wrapping header.
- The document page has one vertical page scroll. Nested vertical scrolling is limited to large grids, long selectors, the sidebar, and overlays.

## 6. Design tokens

Tokens in `src/index.css` are the executable contract.

| Group | Values |
| --- | --- |
| Font | Inter, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif |
| Base text | 13px / 1.4 |
| Spacing | 4, 8, 12, 16, 24, 32px |
| Radius | 4, 6, 8px |
| Page surface | `--pxl-surface-page` |
| Card surface | `--pxl-surface-panel` |
| Raised surface | `--pxl-surface-raised` |
| Header surface | `--pxl-surface-header` |
| Tab surface | `--pxl-surface-tabs` |
| Table header | `--pxl-surface-table-header` |
| Borders | subtle, medium, strong |
| Shadows | card, header, tabs, popover |
| Focus | `--pxl-focus` |

Module color is a subtle accent only. It may color the header edge, links, current workflow step, active/focus cues, and nothing that changes geometry. Header, tab, card, table, and sidebar surfaces remain globally identical.

## 7. Typography

| Element | Standard |
| --- | --- |
| Document number | 20px, semibold, tabular where numeric |
| Related-party identity | 16px, semibold, accent link when clickable |
| Primary amount | 18px, bold, tabular |
| Section title | 14px, semibold, uppercase, restrained tracking |
| Field label | 12px, medium, secondary text |
| Body/value | 13px, regular |
| Caption/provenance | 11px, muted |
| Table header | 12px, semibold, uppercase |

Do not introduce marketing-scale headings, decorative type, module-specific font weights, or low-contrast text.

## 8. Header

The shared header has three ordered regions:

1. back navigation, transaction name, document number, status/meta chips, and primary identity;
2. up to three primary metrics;
3. status/permission-controlled actions.

Rules:

- Minimum desktop content height is 84px; wrapping may increase it.
- Every transaction uses `TransactionPageHeader`.
- Document number, status, and identity appear once.
- Metrics are concise and transaction-specific, but their label/value typography and alignment are fixed.
- Use at most one visually primary action. Secondary and destructive actions move into More when needed.
- Hidden actions are reserved for truly inapplicable/unauthorized operations. Temporarily unavailable actions are disabled with an explanation.
- Error detail belongs in Validation or an alert directly below the workflow, not as a long header string.

## 9. Workflow strip

`TransactionWorkflowBanner` appears directly below the header.

- It uses the same compact steps, connector, current/completed/upcoming states, height, padding, and semantics everywhere.
- Status is never communicated by color alone; each step has text and the current step has `aria-current="step"`.
- Only lifecycle labels and current step vary.
- The strip is not an approval-history replacement; Approval owns approval evidence.

## 10. Information cards

The primary band always contains exactly three equal cards at desktop width.

- Class contract: `pxl-transaction-info-cards` and `pxl-transaction-info-card`.
- Card surface, 1px medium border, 8px radius, 12px padding, and card shadow are fixed.
- Cards size to their actual fields. They have no arbitrary minimum height; cards in a row align at the top.
- Card title uses the shared section title and a subtle bottom divider.
- Use a compact two-column fact/control grid where practical.
- Keep the band to identity and transaction-driving context. Detailed master data, long notes, and system metadata belong in tabs.
- In create/edit modes these cards contain the actual bound document-header controls. They are not read-only summaries of a second form below the tabs.
- Every document-level field has one input owner in the cards. The Lines tab must not repeat customer/supplier, date, branch, currency, payment method/account, reference, memo, source, or status controls.
- A legitimate missing card uses the standard truthful empty state; it does not change the grid.
- Do not use dashboard graphics, oversized totals, decorative icons, or nested cards.

## 11. Standard tabs

The order is fixed:

1. Lines
2. Financial
3. GL Impact
4. Tax Impact
5. Validation
6. Workflow
7. Approval
8. Audit
9. Related Docs
10. Related Party
11. Attachments
12. Activity
13. Notes
14. System

All positions remain visible. Inapplicable or unavailable content uses a truthful empty state; it is not fabricated and the tab does not move.

- Tabs are text-only, 13px, minimum 32px high, and equal-width.
- Active, hover, focus, and disabled behavior are shared.
- Arrow Left/Right, Home, and End move and activate focus.
- Tabs use `role="tablist"`, `role="tab"`, `aria-selected`, `aria-controls`, and one `tabpanel`.
- Tab changes preserve unsaved draft state and must not remount the domain form.

## 12. Active panel and sidebar

The active tab and sidebar share one grid.

- Active panel: raised surface, medium border, 8px-equivalent shared radius, 10px horizontal/8px vertical padding, compact shadow, and natural content height.
- Do not nest a second decorative card immediately inside the panel; shared CSS flattens an unavoidable legacy wrapper.
- Sidebar width is fixed by the responsive grid, never by page content.
- Sidebar panels use one title style, bottom divider, compact spacing, and source-backed content.
- Quick Actions are composed by the shared sidebar renderer and mirror executable header actions; the sidebar does not invent actions.
- Repeated values are allowed only when the sidebar makes an active operational decision materially faster. Avoid duplicating entire Financial, GL, Tax, or party tabs.
- The sidebar begins level with tab content, may be shorter than the main panel, and contains compact operational summaries rather than a second document-information or party card.

## 13. Forms and controls

- Controls use `pxl-input` and a 32px standard minimum height.
- Read-only values use readable text or `pxl-readonly-field`; a view is not a disabled form.
- Labels remain associated with their controls and required state is explicit in text/symbol.
- Selectors support keyboard use, preserve selection, show loading/empty states, and do not reset unrelated draft values.
- Overlays use a portal or equivalent non-clipping layer with a bounded viewport position and a higher z-index than sticky regions.
- Draft-state ownership follows `PXL_TRANSACTION_DRAFT_STATE_STANDARD.md`; field changes are scoped partial updates.

## 14. Tables and totals

Line, application, impact, audit, related-document, and system collections use semantic tables.

- Class contract: `pxl-data-grid`.
- Header cells are 12px uppercase semibold with compact 5px × 10px padding.
- Body cells are 13px with compact 5px × 10px padding and an approximate 30px row target.
- Numeric cells are right-aligned and tabular.
- Hover/selection states are subtle and theme-safe.
- Totals use a stronger top border and table footer surface.
- Large grids scroll within the active panel; frozen identifiers may be used when they improve line processing.
- Totals appear once in the domain table/Financial tab and may be summarized compactly in header/sidebar. Do not render competing full financial summaries.

### Tab content ownership

- Lines begins directly with the line, application, journal, movement, asset, or schedule table. It may include a compact title/helper, Add Line, line totals, and line validation only.
- Financial owns detailed reconciliation; GL Impact owns detailed journal preview/posted rows; Tax Impact owns detailed tax treatment; Validation owns readiness and errors; Approval and Audit own their histories.
- A full GL, tax, financial, validation, approval, or audit panel must not be repeated below the Lines table. The sidebar may show only compact totals/readiness.
- No second transaction header, duplicate Back link, or bottom-only primary action is allowed inside tab content.

## 15. Financial, GL, tax, and inventory presentation

- Financial uses a compact table or aligned label/value summary with one emphasized final total/status.
- GL Impact uses authoritative posting-engine or ledger rows. Separate commercial/settlement and inventory sections when both exist. Show account, debit, credit, memo, entity/dimensions, source, and status when available.
- A non-posting document says `No direct GL posting`. An unsaved posting document says that authoritative impact becomes available after preview/save/post. Never infer entries in the UI.
- Tax Impact uses source-backed classification, base, rate, amount, timing, ATC/reporting destination, and source line when available. Never infer unsupported compliance treatment.
- Inventory impact uses source-backed quantity in/out, warehouse, cost, valuation, document trace, and movement status.
- Every unavailable state distinguishes not applicable, not yet available, not configured, and not exposed by the authoritative query.

## 16. Validation, approval, audit, relations, and system panels

- Validation separates blocking errors, warnings, informational checks, and readiness. Raw exceptions are secondary diagnostic detail.
- Approval shows status, approver, timestamps, comments, next action, and segregation-of-duties restrictions when exposed.
- Audit is chronological and shows actor, event, timestamp, old/new values or transition, source, and reason when exposed.
- Related Docs uses clickable source/target rows with relationship, number, status, amount/quantity where relevant, and trace direction.
- Related Party links to the governed master and distinguishes document snapshots from current master values.
- Attachments, Activity, and Notes use shared table/list/empty patterns and never display fake records.
- System exposes safe operational metadata only; credentials, privileged secrets, and irrelevant internals are prohibited.

## 17. States

Every workspace and tab supports:

- loading: stable skeleton/compact loading state without destroying draft state;
- empty: concise explanation and valid next action when one exists;
- error: user-facing message plus recoverable action;
- permission denied: no executable unauthorized control;
- locked/posted: read-only truth with reversal/adjustment path where governed;
- partial data: visible provenance and truthful unavailable state.

State components use the same padding, typography, border, icon treatment, and theme tokens across modules.

## 18. Theme and accessibility

- Light and dark themes use the same hierarchy and geometry.
- All text meets practical contrast requirements; dark mode must not preserve light-only backgrounds or gray text tokens.
- Focus is always visible.
- Status uses text plus shape/position, not color alone.
- Icon-only controls require accessible names.
- Tables preserve header/cell semantics where practical.
- Actions, tabs, menus, dialogs, and selectors are keyboard operable.
- Reduced-motion preferences must not block state communication.

## 19. Interaction and data integrity

- One routed workspace represents a transaction mode; view and edit retain the same architecture.
- Primary status/permission-aware actions use the top `TransactionPageHeader` action area and remain connected to the domain page's real handlers. A bottom convenience action may exist only when it mirrors the same action model without contradiction.
- Opening a tab, selector, related record, menu, or preview must not reset header or line state.
- A page may mount the domain form only once.
- Posted immutability, period locks, company/branch context, RLS, approvals, and permissions remain server-authoritative.
- Navigation to master and related documents is explicit and preserves unsaved-change safeguards.
- No shared component may fabricate business facts to fill visual space.

## 20. Acceptance contract

A transaction workspace is compliant only when automated or manual evidence confirms:

- exactly one workspace, header, workflow strip, three-card band, tab bar, active panel, and sidebar;
- no document-level controls, Back action, or detailed impact panels duplicated inside Lines;
- the fixed fourteen-tab order and one-row navigation;
- shared header/sidebar/card/table geometry;
- at least 94% viewport use inside AppShell at supported desktop widths;
- no page-level horizontal overflow at 90%, 100%, 110%, and 125%;
- productive information density at 90% and 100% without 67% zoom, artificial blank panels, or fixed-height alignment;
- usable light/dark themes and keyboard navigation;
- no runtime errors, duplicate keys, invalid nesting, or avoidable console warnings;
- source-backed business content and truthful unavailable states;
- domain posting, tax, inventory, permission, and lifecycle tests remain unchanged.

`src/lib/transactionWorkspaceCoverage.ts` is the executable route inventory. Screenshot comparison is evidence of conformance, but a screenshot never proves accounting or security correctness.
