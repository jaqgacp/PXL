# PXL ERP — UI/UX Principles & Navigation Architecture
**Version:** 2.0 (Post-Architecture Review)
**Date:** 2026-06-28
**Authority:** Principal Frontend Architect

> These principles govern every screen, component, and interaction in PXL ERP. No exception is permitted without written architectural approval. A screen that violates these principles is not finished — regardless of whether it functions correctly.

Canonical workspace standards now sit above generic UI guidance for their domains:

- Transaction pages are governed by `docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md`.
- Report pages are governed by `docs/PXL/PXL_STANDARD_REPORT_WORKSPACE.md`.

Use this document for shared visual and interaction principles. Use the workspace standards for page architecture, ownership boundaries, reusable components, and rollout rules.

Active gate: `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md` now controls sequencing. Do not create additional UI standards, dashboards, report pilots, or transaction workspace rollouts until **PXL Accounting Core Ready** is cleared.

Posting behavior is governed by `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md`; UI screens display and explain accounting behavior but must not redefine it.

---

## Table of Contents

1. [The PXL Philosophy](#1-the-pxl-philosophy)
2. [Layout & Navigation](#2-layout--navigation)
3. [Data Grids & Tables](#3-data-grids--tables)
4. [Forms & Data Entry](#4-forms--data-entry)
5. [Interaction & Feedback](#5-interaction--feedback)
6. [Information Design](#6-information-design)
7. [Architecture & Components](#7-architecture--components)
8. [Navigation Structure](#8-navigation-structure)

---

## 1. The PXL Philosophy

### Principle 1 — Professional ERP, Not a Consumer App

PXL is an enterprise accounting system. It is not a social media platform, a project management tool, a note-taking app, or a settings panel. Every design decision must be evaluated against enterprise-grade benchmarks — NetSuite, SAP Business One, Microsoft Business Central.

**The correct reference points:**
- Dense, professional, information-rich
- Top navigation bar (not a sidebar)
- Workflow-oriented screens (not card-browsing experiences)
- Keyboard-operable at every level
- Designed for someone processing 200 transactions per day — not someone visiting once a week

**What this means in Tailwind/Shadcn:**
- Base font size: `text-sm` (`14px`) for all table and form content. Never `text-base` as the default for data grids.
- Compact padding: `p-2` or `px-3 py-2` for table cells and form fields. Never `p-6` on list rows.
- Background: `bg-background` (white/light gray) with `border-border` separators — not soft gradients or pastel cards.
- Use Shadcn's `Table`, `Card`, `Input`, `Select`, `Badge` primitives — never build one-off styled components.

---

### Principle 25 — The Dashboard Is Actionable, Not Decorative

The PXL Dashboard is a command center, not a vanity report. Charts and graphs are decorative if they don't drive action. Every widget on the dashboard must answer the question: **"What do I need to do right now?"**

**The dashboard must surface:**
- Pending Approvals (with one-click approve action inline)
- Unposted Transactions (grouped by module)
- Overdue Receivables (with aging bracket)
- Current Cash Position per bank account
- Upcoming BIR Tax Deadlines (from Tax Calendar — within 7 days in red, within 14 days in orange)
- System Errors and validation failures
- Today's Tasks assigned to the current user

**Implementation:**
- Use `Card` components from Shadcn with `CardHeader`, `CardContent`.
- Each card has a count badge and a direct "View All" or "Take Action" link — never a dead-end widget.
- Use `Badge` with `variant="destructive"` for overdue items. `variant="outline"` with `text-orange-600` for warnings.
- Dashboard layout: CSS Grid `grid-cols-1 md:grid-cols-2 xl:grid-cols-4` for KPI cards, followed by a full-width action table.

---

### Principle 24 — Workspace-Based Homepages

Different roles see a different homepage. Same database. Different workspace. The system reads the user's role on login and renders the appropriate default dashboard layout. A CFO does not need to see petty cash replenishments. A treasury officer does not need to see BIR compliance deadlines by default.

**Defined workspaces:**
| Role | Default Homepage Focus |
| :--- | :--- |
| `accountant` | Trial Balance shortcut, unposted JEs, period-close checklist |
| `treasury` | Cash Position, bank reconciliation status, check vouchers pending release |
| `sales` | AR Aging, overdue collections, open sales orders |
| `compliance` | BIR deadline calendar, unfiled returns, pending 2307s |
| `executive` | Financial KPIs, branch P&L summary, approval queue |
| `system_admin` | User activity, audit log, feature enablement |

**Implementation:** A `WorkspaceLayout` component receives `userRole` as a prop and conditionally renders widget configurations from a `WORKSPACE_CONFIG` constant. Never use inline role-check conditionals scattered across JSX.

---

### Principle 40 — Enterprise Polish (The Final Gate)

Before any screen is considered complete, the developer must answer **all six questions** affirmatively:

1. Would a CFO feel comfortable using this without embarrassment in a board meeting?
2. Would a licensed CPA understand every field and action without reading a manual?
3. Does it look and feel like a premium, paid ERP — not a free CRUD app?
4. Can an accountant process hundreds of transactions per day efficiently on this screen?
5. Is every control (button position, filter, toolbar) in the exact same position as every other screen?
6. Can this scale from one company to 500 companies without a redesign?

If the answer to any question is **"No"** — the UI is not finished. Ship nothing that fails this gate.

---

## 2. Layout & Navigation

### Principle 5 — Every Module Follows an Identical Page Structure

Without exception, every module page follows this exact vertical sequence. Inventing alternative layouts is prohibited.

```
┌─────────────────────────────────────────────┐
│  Breadcrumb  (Home > Module > Sub-module)   │
├─────────────────────────────────────────────┤
│  Page Title  +  Page-Level Action Buttons   │
├─────────────────────────────────────────────┤
│  Toolbar  (New | Import | Export | More)    │
├─────────────────────────────────────────────┤
│  Quick Filters  (Search | Company | Branch  │
│                  Period | Status | Date)     │
├─────────────────────────────────────────────┤
│                                             │
│  Data Grid / Form Body                      │
│                                             │
├─────────────────────────────────────────────┤
│  Pagination  (Showing X–Y of Z | 50/page)  │
├─────────────────────────────────────────────┤
│  Status Footer  (Last Updated | Posted By)  │
└─────────────────────────────────────────────┘
```

**Implementation:**
- Breadcrumb: Shadcn `Breadcrumb` component. `text-sm text-muted-foreground`. Separator: `/`.
- Page Title: `text-xl font-semibold` (never `text-3xl` — this is not a marketing page).
- The entire shell is a shared `<PageShell>` layout component that wraps all module content. Modules only render the Data Grid or Form Body slot.

---

### Principle 6 — Fixed Navigation — Nothing Moves

The top navigation bar, the module header, and the global search bar are permanently fixed. They do not scroll. They do not collapse. They do not disappear on mobile. The user always knows where they are and how to navigate.

**Implementation:**
- Top nav: `fixed top-0 left-0 right-0 z-50 h-14 bg-background border-b border-border`.
- Main content area: `pt-14` to clear the fixed nav.
- The global search bar (`Ctrl+K`) is always visible in the top nav at all viewport sizes.
- Subheader/toolbar: `sticky top-14 z-40 bg-background border-b` — scrolls with page but stays visible below the nav.

---

### Principle 7 — Mega Menu Navigation (Hover Menus, Not Endless Sidebars)

PXL uses a **top navigation mega-menu** pattern, not a collapsible sidebar. The top-level modules are always visible as text tabs. Hovering over a module reveals a structured dropdown showing all sub-modules grouped by category. This is the enterprise ERP standard.

**Top-Level Navigation Tabs:**
`Dashboard | Setup | Master Data | Sales | Purchasing | Inventory | Banking & Treasury | Fixed Assets | Accounting | Compliance | Reports`

**Mega Menu Implementation:**
- Use a custom `MegaMenu` component wrapping Shadcn `NavigationMenu`.
- Each mega-menu panel is a CSS Grid `grid-cols-3 gap-6 p-6` showing sub-module groups as columns.
- Group headers inside the mega menu: `text-xs font-semibold uppercase text-muted-foreground tracking-wide`.
- Links inside the mega menu: `text-sm text-foreground hover:text-primary` with `rounded-sm px-2 py-1 hover:bg-accent` hover state.
- Active module tab: `border-b-2 border-primary text-primary font-medium`.
- Never use a sidebar as the primary navigation pattern.

---

### Principle 29 — Desktop First, Responsive Second

PXL ERP is built for accountants at their desks. The primary design target is wide-screen desktop. Responsive behavior is secondary and must never compromise the desktop experience.

**Design targets in priority order:**
1. `1920px` — Large monitor (primary target for power users)
2. `1600px` — Standard widescreen
3. `1440px` — Laptop/external monitor
4. `1366px` — Minimum supported desktop width

**Implementation:**
- Tailwind breakpoint usage: Design mobile-up is prohibited for ERP data grids. Instead, design at `xl:` and `2xl:` widths first. Add `sm:` and `md:` breakpoints only for layout collapsing — never to reduce data density.
- Data tables on mobile: Horizontal scroll (`overflow-x-auto`) with `min-w-[1200px]` on the table container. Never collapse table columns — that destroys ERP usability.
- Minimum table column width: `min-w-[120px]` per column. Date columns: `min-w-[100px]`. Amount columns: `min-w-[130px] text-right`.

---

## 3. Data Grids & Tables

### Principle 10 — Tables Are the Heart of PXL

Eighty percent of all ERP work happens inside data tables. Tables must receive the most attention, polish, and engineering investment of any component in the system. A table that is slow, inflexible, or unsortable is a failed ERP table.

**Every PXL table must support:**

| Capability | Implementation |
| :--- | :--- |
| Column Sorting | Click column header to sort ASC/DESC. Arrow icon indicates sort direction. |
| Column Filtering | Per-column filter input accessible via column header dropdown. |
| Multi-Row Selection | Checkbox column (first column, sticky left). Select all via header checkbox. |
| Copy Cell / Row | Right-click context menu or `Ctrl+C` on selection. |
| Export (selected or all) | Export to Excel (.xlsx) and CSV. Respects active filters. |
| Sticky Header | `sticky top-0 z-10 bg-background` on `<thead>`. |
| Resizable Columns | Drag column dividers to resize. Persist widths to `localStorage`. |
| Column Chooser | A "Columns" button in the toolbar reveals a checklist of visible/hidden columns. |
| Saved Views | Users can save current filter + column + sort configuration as a named view. |
| Keyboard Navigation | Arrow keys navigate rows. `Enter` opens the selected row. `Space` toggles selection. |
| Row Count | Footer: `Showing {from}–{to} of {total} records`. |

**Styling:**
- Table header: `bg-muted/50 text-xs font-medium uppercase tracking-wide text-muted-foreground`.
- Table row: `text-sm border-b border-border hover:bg-muted/30 transition-colors`.
- Zebra striping: `even:bg-muted/20` — subtle, not harsh.
- Amount columns: always `text-right font-mono`.
- Date columns: `text-muted-foreground text-xs`.

---

### Principle 9 — Fast Lists — Lists Must Never Feel Slow

A list that takes more than 300ms to feel responsive has failed. Users working with thousands of records must experience a snappy, immediate interface.

**Technical requirements:**
- **Server-side pagination:** All list queries use Supabase `.range(from, to)`. Default page size: 50. Never fetch all records.
- **Virtual rendering:** For lists exceeding 1,000 visible rows, use `@tanstack/react-virtual` for row virtualization.
- **Debounced search:** Search input debounced at `300ms` before triggering API call.
- **Optimistic updates:** Row status changes (e.g., approve, post) update the UI immediately before the server confirms.
- **Skeleton loading:** Show `Skeleton` rows (same height as real rows) while the first page loads. Never show a spinner over an empty table.

**Page size options:** `25 | 50 | 100 | 200`. Default: `50`. Persist to user preferences.

---

### Principle 17 — Quick Filters — Always Visible, No Hunting

Every list page must have an immediately visible quick filter bar below the toolbar. Users must never be forced to open an advanced search dialog to apply the most common filters.

**Mandatory quick filters on every list:**
```
[ 🔍 Search... ]  [ Company ▾ ]  [ Branch ▾ ]  [ Period ▾ ]  [ Status ▾ ]  [ Date ▾ ]  [ Advanced ▾ ]
```

**Implementation:**
- Filter bar: `flex items-center gap-2 py-2 px-4 border-b bg-background`.
- Each filter: Shadcn `Select` with `h-8 text-sm` — compact, not full-height.
- Active filter indicator: When a filter is non-default, the dropdown label shows the selected value in `text-primary font-medium`.
- Clear all filters: An `× Clear` button appears when any filter is active.

---

### Principle 18 — Advanced Filters — Hidden Until Needed

Complex filters (tax type, currency, created-by, amount range, approval status) live behind an "Advanced" toggle. They expand into a filter panel below the quick filter bar. They do not open a modal dialog.

**Implementation:**
- Advanced filters panel: `collapsible` — toggled by a Shadcn `Collapsible` component.
- When expanded: renders a `grid grid-cols-3 gap-4 p-4 bg-muted/30 border-b` panel.
- Each advanced filter is a labeled `Select`, `Input`, or `DateRangePicker`.
- Active advanced filters count: `Advanced Filters (3)` label on the toggle button shows how many are active.

---

## 4. Forms & Data Entry

### Principle 11 — Professional, Logically Grouped Forms

A form with 100 fields in a single scrolling wall is not a professional ERP form. Every form must be divided into logical, labeled sections. Each section covers one domain of information.

**Standard form section structure:**
```
┌── General Information ─────────────────────────┐
│  Document No.   Date   Branch   Currency        │
└─────────────────────────────────────────────────┘
┌── Party Information ───────────────────────────┐
│  Customer   TIN   Address   Payment Terms       │
└─────────────────────────────────────────────────┘
┌── Line Items ──────────────────────────────────┐
│  [ Inline table with Add Row / Delete Row ]     │
└─────────────────────────────────────────────────┘
┌── Tax & Totals ────────────────────────────────┐
│  VAT   EWT   Grand Total   Remarks              │
└─────────────────────────────────────────────────┘
┌── Audit ───────────────────────────────────────┐
│  Created By   Created At   Approved By          │
└─────────────────────────────────────────────────┘
```

**Implementation:**
- Each section: Shadcn `Card` with `CardHeader` (section title in `text-sm font-semibold text-muted-foreground uppercase tracking-wide`) and `CardContent`.
- Form fields inside sections: `grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-4`.
- Label: `text-xs font-medium text-muted-foreground` above the input.
- Input: Shadcn `Input` with `h-8 text-sm` (compact, not full-height).
- Read-only fields (computed or posted): `bg-muted text-muted-foreground cursor-not-allowed`.

---

### Principle 12 — Progressive Disclosure

Do not overwhelm the user. Show the essential fields immediately. Advanced or rarely-used settings are collapsed by default and revealed only on user request.

**Implementation:**
- Use Shadcn `Collapsible` for "Advanced Settings" sections.
- Collapsed state label: `▸ Advanced Options (click to expand)` in `text-sm text-muted-foreground`.
- Expanded state: smoothly animates open using `transition-all`.
- Never auto-expand advanced sections on form load unless the section contains a field with a validation error.

---

### Principle 22 — Smart Defaults — Reduce Typing

Every field that can be pre-populated must be pre-populated from context. A user should never re-type information the system already knows.

**Mandatory smart defaults on every new document:**

| Field | Default Source |
| :--- | :--- |
| Company | User's current company context |
| Branch | User's assigned branch |
| Fiscal Period | Current open fiscal period |
| Currency | `PHP` (unless Multi-Currency is enabled) |
| Date | Today's date |
| Created By | Current logged-in user |
| Status | `draft` |

**Implementation:** A `useDocumentDefaults()` hook pulls context from the `useAuthStore()` and `useFiscalPeriodStore()` and returns default values for the `react-hook-form` `defaultValues` object.

---

### Principle 23 — Context Awareness — No Repeated Selection

The system must remember the user's workspace context and never ask the user to re-select the same Company or Branch after they have already set it. Context is session-persistent.

**Implementation:**
- Global state: `useContextStore()` (Zustand store) holds `{ companyId, branchId, fiscalPeriodId }`.
- Context Selector: A compact context bar in the top nav shows `[Company Name] | [Branch] | [FY2026 - Period 6]`. Clicking any item opens a dropdown to change it.
- All API calls automatically inject `company_id` from the context store. No form should require the user to re-select their company on every document.

---

### Principle 33 — Lookup Windows (ERP-Style Selector Popups)

When a field requires selecting a record from a large dataset (Customer, Supplier, Item, GL Account), do NOT use a standard HTML `<select>` or a giant dropdown. Use a **Lookup Window** — a searchable popup panel with a data grid.

**Lookup Window behavior:**
1. User clicks the lookup field (or presses `F4` / `Enter` when focused).
2. A Shadcn `Dialog` opens containing a compact search input and a paginated data grid.
3. User types to filter. Results appear instantly (server-side search, debounced 200ms).
4. User selects a row by clicking it or pressing `Enter`. The dialog closes and the selected value fills the field.
5. User can also type the exact code/ID directly into the field — the system validates it on blur.

**Implementation:**
- `LookupDialog` is a shared, generic component: `<LookupDialog entity="customers" onSelect={handleSelect} />`.
- The trigger is a Shadcn `Input` with a magnifier icon button on the right: `<Search className="h-3.5 w-3.5 text-muted-foreground" />`.
- The dialog grid supports keyboard navigation: arrow keys to move, `Enter` to select, `Esc` to cancel.

---

### Principle 34 — Master Data Never Leaves Context (Inline Creation)

If a user is creating a Sales Invoice and realizes the customer doesn't exist yet, they must be able to create the customer **inline, without losing the Sales Invoice draft**. This is the ERP standard. Forcing the user to navigate away, create the master record, and then return to the document destroys productivity.

**Implementation:**
- A `CreateInlineDialog` is available on every Lookup field via a `+ Create New` option at the bottom of the lookup results.
- Clicking it opens a second Shadcn `Dialog` (nested dialog) with a minimal "quick create" version of the master data form (required fields only).
- On save, the dialog closes, the new record is selected in the parent field, and the user continues filling the document.
- The parent document draft is never lost — it is maintained in the form state throughout.

---

## 5. Interaction & Feedback

### Principle 3 — Less Clicking — Every Click Has a Cost

Every additional click is a productivity tax on the user. Before adding any navigation step, ask: can this be accomplished without this click? The goal is to perform a complete workflow in the minimum number of interactions.

**Efficiency targets:**

| Action | Maximum Clicks |
| :--- | :--- |
| Open a specific customer's outstanding invoices | 2 clicks (open customer → click "Invoices" tab) |
| Approve a pending document from the dashboard | 1 click (inline approve button) |
| Create a new Sales Invoice from a Sales Order | 1 click ("Create Invoice" action on the SO) |
| Apply a payment to an invoice | 2 clicks (open invoice → "Receive Payment") |
| Post a journal entry after approval | 1 click ("Post" button) |

**Implementation:**
- Action buttons on list rows: Show contextual action buttons on row hover (`opacity-0 group-hover:opacity-100 transition-opacity`).
- Inline quick-approve: On the Pending Approvals dashboard widget, each row has an inline `Approve` / `Reject` button — no need to open the document.
- Document actions must use Shadcn `DropdownMenu` for secondary actions, keeping the primary action as a prominent `Button`.

---

### Principle 4 — Keyboard First — Every Action Must Be Keyboard-Operable

PXL is used by accountants who process hundreds of documents per day. For power users, the mouse is slower than the keyboard. Every important action must be reachable without a mouse.

**Mandatory keyboard shortcuts:**

| Shortcut | Action |
| :--- | :--- |
| `Ctrl+K` | Open Global Command Palette / Search |
| `Ctrl+S` | Save current form |
| `Esc` | Cancel / Close dialog / Clear selection |
| `Enter` | Open selected row / Confirm action |
| `Tab` / `Shift+Tab` | Navigate between form fields |
| `Arrow Up/Down` | Navigate rows in data grids |
| `Arrow Left/Right` | Navigate table columns when focused |
| `F4` or `Enter` (on lookup) | Open lookup window |
| `Ctrl+N` | Create New (in current module) |
| `Ctrl+P` | Print current document |
| `Ctrl+Z` | Undo (in forms, before save) |

**Implementation:**
- Use the `useHotkeys` hook (from `react-hotkeys-hook`) for global shortcuts.
- Register module-level shortcuts in each page's `useEffect`.
- The Shadcn `Command` component (`cmdk`) powers the `Ctrl+K` global command palette.
- All Shadcn components (Dialog, Select, DropdownMenu, Table rows) support keyboard navigation natively — use them as-is.

---

### Principle 8 — Search Everywhere

Everything in PXL must be searchable. The global search (`Ctrl+K`) is not just for navigation — it finds live records across all modules.

**Global Search scope (in order of priority):**
1. Navigation shortcuts (go to any module screen)
2. Customer by name or TIN
3. Supplier by name or TIN
4. Sales Invoice by number or amount
5. Purchase Invoice by number or supplier invoice number
6. Journal Entry by number or description
7. GL Account by code or name
8. Employee by name
9. Any document number across all modules

**Implementation:**
- Shadcn `CommandDialog` with `CommandInput`, `CommandList`, `CommandGroup`, and `CommandItem`.
- Each search category is a `CommandGroup`.
- Results are fetched via debounced Supabase full-text search (`fts` column or `ilike` queries).
- Recent items (last 10 viewed documents) are shown immediately on open, before any typing.

---

### Principle 19 — Empty States — Never a Blank Screen

When a list has no records (either because none exist or because the current filter matches nothing), the screen must never be blank. An empty state communicates what is missing and tells the user what to do next.

**Every empty state must include:**
1. A descriptive icon (from the icon library — relevant to the entity)
2. A headline: `"No [Entity Name] Found"` (e.g., "No Sales Invoices Found")
3. A sub-line: `"Try adjusting your filters or create a new record"` (contextually appropriate)
4. One or two action buttons: `Create New [Entity]` and `Import [Entity]`

**Implementation:**
- Reusable `<EmptyState icon={Icon} title="..." description="..." actions={[...]} />` component.
- Icon: `h-12 w-12 text-muted-foreground/50` — visible but not distracting.
- Container: `flex flex-col items-center justify-center py-16 text-center`.

---

### Principle 20 — Loading States — Never a Frozen Screen

While data is loading, the interface must communicate progress. A blank white area during a data fetch looks like a broken application.

**Loading state hierarchy:**
1. **Initial page load:** Show `Skeleton` rows in the table (same number as expected page size). Skeleton rows use `animate-pulse bg-muted` on placeholder cells.
2. **Filter/sort change:** Show a `Loader2` spinner icon in the toolbar (subtle, `h-4 w-4 animate-spin text-muted-foreground`). Keep existing rows visible until new data arrives.
3. **Form submission:** Disable the submit button and show `<Loader2 className="animate-spin" />` inside the button.
4. **Long operations (export, report generation):** Use a `Progress` bar in a `Toast` notification.

Never show a full-page spinner overlay. It blocks the UI and looks unprofessional.

---

### Principle 21 — Error Messages — Always Specific, Never Generic

A user who receives `"Error 500"` or `"Something went wrong"` cannot fix the problem. Error messages in PXL must identify the exact cause and, where possible, tell the user how to resolve it.

**Error message format:**
```
Cannot [action verb] [entity name].
Reason: [specific cause in plain language].
[Optional: Link to the conflicting record, or suggested resolution]
```

**Examples:**

| Bad | Good |
| :--- | :--- |
| `Error 500` | `Cannot create Company. Reason: TIN '123-456-789-000' already exists on "ABC Corp".` |
| `Validation error` | `Cannot post Journal Entry. Reason: Fiscal Period June 2026 is closed. Contact your controller to unlock it.` |
| `Failed` | `Cannot save Supplier. Reason: "Email" must be a valid email address.` |
| `Duplicate entry` | `Cannot save Item. Reason: Item Code "RM-001" already exists. Use a different code.` |

**Implementation:**
- Form field errors: Shadcn's `FormMessage` component under each field (`text-xs text-destructive`).
- Toast errors for server-side failures: Shadcn `toast({ variant: "destructive", title: "Cannot Post Journal Entry", description: "..." })`.
- Never expose raw database error messages to the user. Parse them in a `handleSupabaseError(error)` utility function.

---

### Principle 28 — No Popup Abuse — Prefer Slide Panels and Drawers

Modals are disruptive. They block the entire screen and break context. Use the least intrusive UI pattern that accomplishes the goal.

**Decision hierarchy:**

| Scenario | Preferred Pattern |
| :--- | :--- |
| Viewing document details without editing | Slide-in `Sheet` (Shadcn `Sheet` with `side="right"`) |
| Editing a simple 2–3 field record | Inline row edit or compact `Dialog` |
| Creating a complex document | Full page navigation |
| Confirming a destructive action (delete, void, cancel) | `AlertDialog` (Shadcn) — always, no exceptions |
| Displaying information context (help, hints) | `Popover` or `Tooltip` |
| Quick create from a lookup | Nested `Dialog` (scoped, compact) |

**Implementation:**
- Document preview: `<Sheet open={isOpen} onOpenChange={setIsOpen}><SheetContent side="right" className="w-[600px] sm:max-w-[600px]">`.
- Destructive confirmation: Always use Shadcn `AlertDialog` with explicit `AlertDialogTitle` and `AlertDialogDescription`. The cancel button is always on the left; the destructive action button is on the right in `variant="destructive"`.

---

### Principle 37 — Fast Perception — Everything Must Feel Instant

The UI must feel instantaneous even when the network is not. Users perceive latency as a quality problem. Slow interfaces erode trust in the software.

**Techniques in priority order:**

| Technique | When to Apply |
| :--- | :--- |
| **Optimistic UI** | Status changes, approvals, toggles — update the UI before server confirms |
| **Skeleton Loading** | All table and card initial loads |
| **Lazy Loading** | Route-level code splitting with `React.lazy()` per module |
| **Virtual Scrolling** | Any list that may exceed 500 visible rows |
| **Local Cache** | Lookup data (currencies, branches, GL accounts) cached in memory for the session |
| **Prefetching** | Hover over a row for 300ms → prefetch the document detail |
| **Debouncing** | All search inputs: 300ms debounce before API call |

**Implementation:**
- Use TanStack Query (`@tanstack/react-query`) for all data fetching. Its cache prevents redundant network calls.
- Optimistic updates: `useMutation` with `onMutate` to update the query cache immediately, `onError` to roll back.
- Route splitting: `const SalesModule = React.lazy(() => import('./modules/sales'))` wrapped in `<Suspense fallback={<PageSkeleton />}>`.

---

## 6. Information Design

### Principle 2 — Information First — Every Pixel Must Provide Value

ERP users are working, not browsing. Large white spaces, hero images, decorative backgrounds, and oversized typography are the visual language of consumer apps. PXL's visual language is **information density**.

**Bad (consumer pattern):**
```
Customer
[  48px of empty space  ]
Name: ABC Corp
```

**Good (ERP pattern):**
```
Customer: ABC Corp          TIN: 123-456-789-000
Tax Type: VAT               Branch: Makati
Status:  Active             Outstanding: ₱1,245,000
Last Invoice: INV-2026-0542 (2026-06-20)
```

**Implementation:**
- List rows: `py-2 px-4` maximum. Never `py-6` for data rows.
- Master data cards: Show at minimum 6–8 key fields in the header card, not just the name.
- Summary cards in document headers: Use a `grid grid-cols-3 xl:grid-cols-5 gap-4` info grid showing all relevant header fields without scrolling.
- Avoid `mt-12` spacers between sections. Use `border-b` dividers with `my-4` at most.

---

### Principle 13 — Readability — Consistent Typography and Spacing

Random font sizes, inconsistent label alignment, and uneven spacing make forms look unfinished and unprofessional.

**Typography scale (strict):**

| Element | Class |
| :--- | :--- |
| Page Title | `text-xl font-semibold` |
| Section Header | `text-sm font-semibold uppercase tracking-wide text-muted-foreground` |
| Field Label | `text-xs font-medium text-muted-foreground` |
| Field Value / Input | `text-sm` |
| Table Header | `text-xs font-medium uppercase tracking-wide` |
| Table Cell | `text-sm` |
| Amount (numeric) | `text-sm font-mono tabular-nums text-right` |
| Muted / Secondary | `text-xs text-muted-foreground` |
| Error Text | `text-xs text-destructive` |

**Alignment rules:**
- All form labels align left, directly above their input.
- All numeric columns in tables are `text-right`.
- All currency amounts use `tabular-nums` to ensure digit alignment.
- All date columns use `text-muted-foreground` — they are secondary information.

---

### Principle 14 — Colors Have Meaning — Never Random

Color is a communication tool in PXL, not a decoration. Every color usage carries a specific semantic meaning. Using blue for a warning or red for informational text is a UX defect.

**Semantic color map:**

| Color | Semantic Meaning | Tailwind / Shadcn Token |
| :--- | :--- | :--- |
| Blue | Informational, links, primary actions | `text-blue-600 / bg-blue-50` |
| Green | Success, posted, active, matched | `text-green-600 / bg-green-50` |
| Orange / Amber | Warning, pending, due soon, draft | `text-amber-600 / bg-amber-50` |
| Red | Error, overdue, rejected, cancelled, destructive | `text-red-600 / bg-red-50` |
| Gray | Inactive, disabled, closed, muted | `text-gray-500 / bg-gray-100` |
| Purple | Special states (e.g., amended returns) | `text-purple-600 / bg-purple-50` |

Never assign colors arbitrarily. If a designer or developer wants to use a color, they must identify which semantic meaning it expresses.

---

### Principle 15 — Status Badges — Always Badges, Never Plain Text

Document statuses are the most frequently scanned piece of information on any ERP list. They must always render as colored badge chips, never as plain text. A list of 50 invoices where statuses are displayed as plain gray text is unreadable.

**Status badge mappings:**

| Status | Shadcn Variant | Color |
| :--- | :--- | :--- |
| `draft` | `outline` | Gray text |
| `for_approval` | `secondary` | Blue |
| `approved` | `secondary` | Blue filled |
| `posted` | `default` | Green |
| `filed` | `default` | Green filled |
| `cancelled` | `destructive` | Red |
| `rejected` | `destructive` | Red |
| `voided` | `destructive` | Red muted |
| `closed` | `outline` | Gray muted |
| `amended` | custom | Purple |
| `overdue` | `destructive` | Red |
| `pending` | `secondary` | Amber |

**Implementation:** `<StatusBadge status={document.status} />` — a single shared component that maps status strings to the correct Shadcn `Badge` variant and color. No inline badge styling scattered across modules.

---

### Principle 16 — One Toolbar Standard — Button Order Never Changes

The toolbar on every list page and every form page follows an identical button order. A user who learns the toolbar on the Sales Invoice page knows the toolbar on the Purchase Invoice page. Zero relearning cost.

**List Page Toolbar (left to right):**
```
[ + New ]  [ ↑ Import ]  [ ↓ Export ]  [ ✓ Approve ]  [ 🖨 Print ]  [ ⋯ More ▾ ]
```

**Form Page Toolbar (left to right):**
```
[ 💾 Save ]  [ 💾 Save & New ]  [ ⧉ Duplicate ]  [ 🗑 Delete ]  [ ✕ Cancel ]
```

**Document Action Toolbar (when a document is open in view mode):**
```
[ ✏ Edit ]  [ ✓ Approve ]  [ ⬆ Post ]  [ 🖨 Print ]  [ ⋯ More ▾ (Void, Cancel, Duplicate) ]
```

**Rules:**
- Buttons that are not applicable to the current document state are `disabled` (grayed), not hidden. A "Post" button on a Draft document is disabled. It only enables after approval.
- Destructive actions (Delete, Void, Cancel) always live inside the `More ▾` dropdown unless they are the only action available.
- The `Save` button is always the leftmost action on a form. `Cancel` is always the rightmost.

---

## 7. Architecture & Components

### Principle 32 — Components Before Pages — Never Build a Screen, Build Parts

Every UI element in PXL is a reusable component before it is a page. Pages are assemblies of components. A page that contains unique, non-reusable markup is an architectural failure.

**Component hierarchy (build in this order):**

```
Atom          → Button, Input, Badge, Icon, Label
Molecule      → FormField (Label + Input + Error), StatusBadge, AmountCell, DateCell
Organism      → DataTable, FilterBar, Toolbar, FormSection, LookupDialog, DocumentHeader
Template      → PageShell, ListPageLayout, FormPageLayout, DocumentLayout
Page          → SalesInvoiceList, SalesInvoiceForm, CustomerList, etc.
```

**Naming convention:**
- Components: `PascalCase` in `/src/components/`
- Shared components: `/src/components/shared/`
- Module-specific components: `/src/components/sales/SalesInvoiceStatusBadge.tsx`
- A component that is used in more than one module must move to `/src/components/shared/`.

---

### Principle 31 — One Design Language — Total Consistency

One button library. One input library. One icon library. One badge pattern. One dialog pattern. No exceptions. A screen that introduces a new UI pattern — a custom-styled div that looks like a button, a bespoke dropdown, a hand-crafted badge — is not finished.

**The design language stack:**
- **Component Library:** Shadcn UI (exclusively)
- **Styling:** Tailwind CSS (exclusively — no inline `style={{}}` except for dynamic widths)
- **Icons:** Lucide React (exclusively — no mixing with Heroicons, Material Icons, or Font Awesome)
- **Date Picker:** Shadcn `Calendar` + `Popover`
- **Rich Dropdowns:** Shadcn `Command` inside `Popover`
- **Notifications:** Shadcn `Toaster` + `useToast()`
- **Forms:** `react-hook-form` + `zod` (exclusively — no uncontrolled forms)

If a required component doesn't exist in Shadcn, build it using Shadcn primitives (Radix UI) and Tailwind. Never bring in a second component library.

---

### Principle 35 — Professional Icons — One Library Only

PXL uses **Lucide React** for all icons. No other icon library is permitted. Mixing icon styles (some outlined, some filled, some solid) creates visual inconsistency that signals low-quality software.

**Icon usage rules:**
- Toolbar action icons: `h-4 w-4` — always accompanied by a text label
- Table row action icons: `h-3.5 w-3.5` — may appear without text inside icon buttons
- Status/indicator icons: `h-3.5 w-3.5` inside badge components
- Empty state icons: `h-12 w-12 text-muted-foreground/40`
- Navigation icons: `h-4 w-4` — always with text label in the mega menu

Never use an icon without an accessible `aria-label` or accompanying text label.

---

### Principle 36 — Accessibility — Not Optional

Accessibility in PXL is a baseline requirement, not a bonus. An interface that cannot be used with a keyboard or screen reader fails Principle 4 and fails BIR CAS audit requirements for software usability standards.

**Mandatory accessibility requirements:**

| Requirement | Implementation |
| :--- | :--- |
| Visible focus ring | `focus-visible:ring-2 focus-visible:ring-ring` on all interactive elements. Never `outline-none` without a replacement. |
| Keyboard navigation | All modals, dropdowns, tables, and forms must be fully keyboard-operable. |
| Color contrast | All text must meet WCAG AA contrast ratio (4.5:1 for normal text, 3:1 for large text). Never use `text-gray-300` on white. |
| Minimum font size | `14px` (`text-sm`) for all readable content. Never `text-xs` for body content — only for labels and secondary metadata. |
| ARIA labels | All icon-only buttons: `aria-label="[action description]"`. All data tables: `aria-label="[entity] list"`. |
| Screen reader compatibility | Use semantic HTML (`<table>`, `<th>`, `<caption>`, `<form>`, `<label>`) — never `<div>` soup for data grids. |

---

### Principle 26 — Audit Visibility — One Click Away

Every document in PXL has a complete, immutable audit trail. This audit trail must be visible to authorized users without navigation to another screen.

**Every document must expose:**
- `Created By` and `Created At`
- `Updated By` and `Updated At`
- `Approved By` and `Approved At` (if applicable)
- `Posted By` and `Posted At` (if applicable)
- Full audit trail history (via a collapsible `Audit Trail` section at the bottom of every document form)

**Implementation:**
- `AuditTrail` is a shared component: `<AuditTrailSection documentId={id} documentType="sales_invoice" />`.
- It renders a collapsible section showing a chronological list of all `sys_audit_logs` entries for this record.
- Each audit entry shows: `[timestamp] [user_name] [action: INSERT/UPDATE/DELETE] [changed fields]`.
- The section is collapsed by default. Label: `▸ Audit Trail (12 entries)`.

---

### Principle 27 — Drill Down Everywhere — No Dead Ends

Every financial figure in PXL is a hyperlink to its source. A user looking at a Balance Sheet must be able to click any amount and trace it all the way to the originating source document.

**Drill-down chain:**
```
Financial Statement
  → Trial Balance (filtered to that account)
    → General Ledger Entries (filtered to that account + period)
      → Journal Entry (the specific voucher)
        → Source Document (Sales Invoice / Purchase Bill / PCV / etc.)
          → Customer / Supplier master record
```

**Implementation:**
- Every amount in a report is rendered as a `<Button variant="link" className="h-auto p-0 text-sm font-mono">` that navigates to the next drill-down level.
- The drill-down target URL carries query parameters: `/accounting/gl?account_id=X&period_start=Y&period_end=Z`.
- Dead ends are not permitted. If a figure cannot be drilled further, it means the source linking is incomplete — fix the data model, not the UI.

---

### Principle 30 — No Hidden Features — Visibility, Not Mystery

Users must never need to guess where an action is or whether a feature exists. All actions available to the user's role are visible in the interface. Role-based permissions control what is **enabled** — they do not hide features arbitrarily.

**The rule:**
- A feature that exists for a role is **visible** in the menu.
- A feature that the user's role cannot access is **visible but disabled** with a tooltip: `"You don't have permission to [action]. Contact your system administrator."`.
- A feature that is not licensed (disabled via `sys_feature_enablement`) is completely absent from the menu — users do not see features that are not provisioned for their company.

This means: the Mega Menu is dynamically built from `sys_feature_enablement` flags. If `fixed_assets = false`, the entire Fixed Assets menu node is absent.

---

### Principle 38 — No Duplicate Screens — Reuse Components

A list page and a view page of the same entity must not be two separate, independently styled pages. The view is a drill-down state of the list. Edit is a state of the view. Build once, parameterize by mode.

**Pattern:**
```
/sales/invoices              → List mode (DataTable)
/sales/invoices/:id          → View mode (DocumentLayout, read-only)
/sales/invoices/:id/edit     → Edit mode (DocumentLayout, editable)
/sales/invoices/new          → Create mode (DocumentLayout, empty)
```

All four routes render the same `SalesInvoiceDocument` component with a `mode` prop. The component handles read-only vs. editable rendering internally.

---

### Principle 39 — Document-Centric UX — Every Document Has the Same Anatomy

PXL revolves around documents. Every transactional document (Sales Invoice, Purchase Bill, Journal Entry, Check Voucher, Asset Acquisition, VAT Return) shares a common structural anatomy. Users who understand one document understand all documents.

**Universal Document Anatomy:**

```
┌── Document Header ──────────────────────────────────────────┐
│  [Document Number]  [Status Badge]  [Action Toolbar]        │
│  [Key Fields: Date, Branch, Party, Totals]                  │
└─────────────────────────────────────────────────────────────┘
┌── Line Items Table ─────────────────────────────────────────┐
│  [Editable data grid with Add Row / Delete Row]             │
│  [Totals summary at bottom of grid]                         │
└─────────────────────────────────────────────────────────────┘
┌── Tabs ─────────────────────────────────────────────────────┐
│  [Posting Preview] [Attachments] [Comments] [Audit Trail]   │
│  [Related Documents] [Approval History]                     │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:**
- `DocumentLayout` is the shared wrapper component: `<DocumentLayout title="Sales Invoice" status={status} toolbar={<InvoiceToolbar />}>`.
- Tab navigation at the bottom: Shadcn `Tabs` with `TabsList` and `TabsContent`.
- Tabs present on every document: `Details | Posting Preview | Attachments | Comments | Audit Trail`.
- Module-specific tabs (e.g., `Related Documents`, `Approval Chain`) are added as additional `TabsTrigger` items via a `tabs` prop.

---

## 8. Navigation Structure

The following is the complete, authoritative PXL ERP navigation tree as of Architecture Version 2.0. This reflects all modules built, reviewed, and finalized in the current architecture session. All additions (Exchange Rates, Check Vouchers, General Ledger Entries, Unified Approval Workflow, Global Feature Enablement, System Audit Log) are incorporated.

```
PXL ERP
│
├─ 1. Dashboard
│
├─ 2. Setup
│  ├─ Organization
│  │  ├─ Company Setup
│  │  ├─ Branch Setup
│  │  ├─ Department Setup
│  │  ├─ Cost Centers
│  │  ├─ CAS Registrations
│  │  ├─ Company Bank Accounts
│  │  └─ Compliance Profile
│  │
│  ├─ System Controls
│  │  ├─ [Number Series]
│  │  │  ├─ Sales Documents
│  │  │  ├─ Purchasing Documents
│  │  │  ├─ Accounting Documents
│  │  │  └─ Compliance Documents
│  │  │
│  │  ├─ ATP Monitoring
│  │  │
│  │  ├─ [Feature Settings]
│  │  │  ├─ Global Feature Enablement    ← NEW (sys_feature_enablement)
│  │  │  ├─ Inventory Settings
│  │  │  ├─ Fixed Assets Settings
│  │  │  ├─ Petty Cash Settings
│  │  │  ├─ Bank Reconciliation Settings
│  │  │  └─ Budget Settings
│  │  │
│  │  └─ [Approval Matrix]
│  │     ├─ Unified Approval Workflow    ← NEW (approval_workflows table)
│  │     ├─ Sales Approval              ← Redirects to Unified
│  │     ├─ Purchasing Approval         ← Redirects to Unified
│  │     ├─ Payment Approval            ← Redirects to Unified
│  │     ├─ Journal Approval            ← Redirects to Unified
│  │     └─ Master Data Approval        ← Redirects to Unified
│  │
│  ├─ Document & Validation
│  │  ├─ [Document Controls]
│  │  │  ├─ Status Controls
│  │  │  ├─ Posting Controls
│  │  │  ├─ Void Controls
│  │  │  └─ Reversal Controls
│  │  └─ [Validation Rules]
│  │     ├─ Master Data Rules
│  │     ├─ Transaction Rules
│  │     ├─ Posting Validation Rules
│  │     └─ Period Controls
│  │
│  ├─ Accounting Setup
│  │  ├─ Fiscal Years
│  │  ├─ Fiscal Calendar
│  │  ├─ Chart of Accounts
│  │  ├─ Currency Setup
│  │  ├─ Exchange Rates                  ← NEW (daily Forex rates, multi-currency)
│  │  ├─ Opening Balances
│  │  ├─ Financial Statement Fields
│  │  └─ GL Posting Configuration
│  │
│  ├─ Tax Setup
│  │  ├─ BIR Form Configuration
│  │  ├─ Tax Codes
│  │  ├─ VAT Codes
│  │  ├─ EWT Codes
│  │  ├─ FWT Codes
│  │  ├─ Percentage Tax Codes
│  │  ├─ ATC Codes
│  │  └─ Tax Calendar                   ← UPDATED (auto-generates from Compliance Profile)
│  │
│  └─ System Audit Log                  ← NEW (sys_audit_logs, INSERT-ONLY)
│
├─ 3. Master Data
│  ├─ Parties
│  │  ├─ Customers
│  │  ├─ Suppliers
│  │  └─ Personnel / Employees Lite
│  │
│  ├─ Items & Services
│  │  ├─ Item Categories
│  │  ├─ Units of Measure
│  │  ├─ Items
│  │  └─ Services
│  │
│  ├─ Inventory Master
│  │  ├─ Warehouses
│  │  └─ Warehouse Stock Settings
│  │
│  └─ Shared
│     └─ Payment Terms
│
├─ 4. Sales
│  ├─ Transactions
│  │  ├─ Quotations
│  │  ├─ Sales Orders
│  │  ├─ Delivery Receipts
│  │  ├─ Sales Invoices
│  │  ├─ Cash Sales
│  │  ├─ Receipts
│  │  ├─ Credit Memos
│  │  ├─ Debit Memos
│  │  └─ Customer Returns
│  │
│  ├─ Receivables
│  │  ├─ Customer Ledger
│  │  ├─ AR Aging
│  │  └─ Collection Monitoring
│  │
│  ├─ Tax Review
│  │  ├─ Output VAT Review
│  │  ├─ Percentage Tax Review
│  │  └─ 2307 Received Review
│  │
│  └─ Registers
│     ├─ Sales Invoice Register
│     ├─ Receipt Register
│     ├─ Credit Memo Register
│     ├─ Debit Memo Register
│     └─ SLS
│
├─ 5. Purchasing
│  ├─ Transactions
│  │  ├─ Purchase Orders
│  │  ├─ Receiving Reports
│  │  ├─ Vendor Bills
│  │  ├─ Cash Purchases
│  │  ├─ Payment Vouchers
│  │  ├─ Vendor Credits
│  │  ├─ Debit Memos to Suppliers
│  │  └─ Purchase Returns
│  │
│  ├─ Payables
│  │  ├─ Supplier Ledger
│  │  ├─ AP Aging
│  │  └─ Payment Monitoring
│  │
│  ├─ Tax Review
│  │  ├─ Input VAT Review
│  │  ├─ EWT Summary
│  │  └─ 2307 Issued Review
│  │
│  └─ Registers
│     ├─ Vendor Bill Register
│     ├─ Payment Register
│     ├─ Debit Memo Register
│     └─ SLP
│
├─ 6. Inventory
│  ├─ Operations
│  │  ├─ Inventory Dashboard
│  │  ├─ Stock Adjustment
│  │  ├─ Stock Transfer
│  │  ├─ Goods Issue
│  │  ├─ Physical Count
│  │  ├─ Inventory Movements
│  │  └─ Inventory Valuation
│  │
│  └─ Master Data
│     ├─ Items
│     └─ Warehouses
│
├─ 7. Banking & Treasury
│  ├─ Petty Cash
│  │  ├─ Petty Cash Fund Setup
│  │  ├─ Petty Cash Vouchers
│  │  ├─ Petty Cash Replenishment
│  │  └─ Cash Count Sheet
│  │
│  ├─ Bank Operations
│  │  ├─ Fund Transfers
│  │  ├─ Inter-Branch Transfers
│  │  ├─ Bank Adjustments
│  │  ├─ Bank Reconciliation
│  │  ├─ Outstanding Checks
│  │  └─ Deposits in Transit
│  │
│  └─ Payables                          ← NEW SECTION
│     └─ Check Vouchers                 ← NEW (AP payment, EWT deduction, 2307 auto-gen)
│
├─ 8. Fixed Assets
│  ├─ Operations
│  │  ├─ Fixed Asset Dashboard
│  │  ├─ Asset Register                 ← UPDATED (net_book_value = GENERATED ALWAYS AS)
│  │  ├─ Asset Acquisition
│  │  ├─ Depreciation
│  │  ├─ Disposal
│  │  ├─ Transfer
│  │  └─ Impairment
│  │
│  └─ Setup
│     ├─ Asset Categories
│     └─ Depreciation Profiles
│
├─ 9. Accounting
│  ├─ Journal Entries
│  │  ├─ General Ledger Entries         ← NEW (immutable ledger, partitioned by year)
│  │  ├─ Journal Entries
│  │  └─ Recurring Journal Templates
│  │
│  ├─ Ledgers
│  │  ├─ General Ledger
│  │  ├─ Account Detail Ledger
│  │  └─ Trial Balance
│  │
│  ├─ Subsidiary Ledgers
│  │  ├─ Customer Ledger (Accounting View)
│  │  ├─ Supplier Ledger (Accounting View)
│  │  └─ Control Account Reconciliation ← UPDATED (PostgreSQL trigger enforcement)
│  │
│  ├─ Schedules
│  │  ├─ Amortization Schedules         ← REWRITTEN (clean schema, GL-linked)
│  │  └─ Revenue Recognition Schedules
│  │
│  └─ Period Management
│     ├─ Period Closing
│     ├─ Fiscal Locks
│     ├─ Posting Review
│     ├─ Reversal Review
│     ├─ Amortization Run
│     ├─ Revenue Recognition Run
│     └─ Auto Reversal Run
│
├─ 10. Compliance
│  ├─ Percentage Tax
│  │  ├─ PT Dashboard
│  │  ├─ PT Working Papers
│  │  ├─ PT Quarterly Return 2551Q
│  │  ├─ PT Reconciliation
│  │  └─ PT Summary Register
│  │
│  ├─ VAT
│  │  ├─ VAT Dashboard
│  │  ├─ VAT Working Papers
│  │  ├─ Output VAT Summary
│  │  ├─ Input VAT Summary
│  │  ├─ VAT Reconciliation
│  │  ├─ VAT Return 2550M               ← REWRITTEN (full BIR box mapping Box 12–24)
│  │  ├─ VAT Return 2550Q               ← REWRITTEN (full BIR box mapping Box 19A–29)
│  │  ├─ SLS
│  │  ├─ SLP
│  │  ├─ SLSP Export                    ← REWRITTEN (all mandatory BIR DAT columns)
│  │  └─ RELIEF Export                  ← REWRITTEN (all 13 BIR RELIEF DAT columns)
│  │
│  ├─ Withholding Tax
│  │  ├─ WT Dashboard
│  │  ├─ EWT Working Papers
│  │  ├─ EWT Payable Summary
│  │  ├─ EWT Receivable Summary
│  │  ├─ ATC Summary
│  │  ├─ 1601EQ Working Papers
│  │  ├─ 1601EQ Quarterly Return
│  │  ├─ QAP
│  │  ├─ SAWT
│  │  ├─ 2307 Certificates Issued
│  │  ├─ 2307 Certificates Received
│  │  ├─ 2306 Certificates             ← REWRITTEN (FWT certificate, ATC code reference)
│  │  └─ [Final Withholding Tax]
│  │     ├─ FWT Working Papers
│  │     ├─ 1601FQ Working Papers
│  │     └─ 1601FQ Quarterly Return
│  │
│  ├─ Income Tax
│  │  ├─ Income Tax Dashboard
│  │  ├─ Taxable Income Computation
│  │  ├─ Book-to-Tax Reconciliation
│  │  ├─ OSD Computation
│  │  ├─ NOLCO Schedule
│  │  ├─ Tax Credits Schedule
│  │  ├─ [Individual (Sole Proprietor)]
│  │  │  ├─ 1701Q Quarterly ITR
│  │  │  └─ 1701 Annual ITR
│  │  └─ [Corporate / OPC / Partnership]
│  │     ├─ 1702Q Quarterly ITR
│  │     ├─ 1702RT Annual ITR
│  │     └─ MCIT Computation
│  │
│  ├─ BIR Books
│  │  ├─ Books Dashboard
│  │  ├─ General Journal
│  │  ├─ General Ledger Book
│  │  ├─ Cash Receipts Book
│  │  ├─ Cash Disbursements Book
│  │  ├─ Sales Journal
│  │  ├─ Cash Sales Journal
│  │  ├─ Purchase Journal
│  │  ├─ Cash Purchases Journal
│  │  ├─ AR Subsidiary Ledger
│  │  ├─ AP Subsidiary Ledger
│  │  ├─ Inventory Subsidiary Ledger
│  │  └─ Fixed Asset Register
│  │
│  └─ Audit & CAS
│     ├─ CAS Dashboard
│     ├─ Transaction Audit Log          ← Powered by sys_audit_logs
│     ├─ Master Data Change Log         ← Powered by sys_audit_logs
│     ├─ System Parameter Logs
│     ├─ User Activity Log
│     ├─ Attachment Register
│     ├─ Document Void Register
│     ├─ ATP Usage Log
│     ├─ DAT File Generation
│     ├─ CAS Audit Report
│     └─ Export History
│
└─ 11. Reports
   ├─ Financial Statements
   │  ├─ Balance Sheet
   │  ├─ Income Statement
   │  ├─ Statement of Cash Flows
   │  ├─ Statement of Changes in Equity
   │  └─ Comparative Financial Statements
   │
   ├─ Trial Balance
   │  ├─ Unadjusted Trial Balance
   │  ├─ Adjusted Trial Balance
   │  └─ Post-Closing Trial Balance
   │
   ├─ Tax Reports
   │  ├─ Output VAT Summary
   │  ├─ Input VAT Summary
   │  ├─ Percentage Tax Summary
   │  ├─ EWT Summary
   │  ├─ FWT Summary
   │  ├─ 2307 Issued Listing
   │  └─ 2307 Received Listing
   │
   ├─ Aging Reports
   │  ├─ AR Aging
   │  └─ AP Aging
   │
   ├─ Bank Reports
   │  ├─ Bank Position Report
   │  ├─ Bank Reconciliation Summary
   │  └─ Outstanding Checks Report
   │
   ├─ Inventory Reports
   │  ├─ Inventory Valuation
   │  ├─ Stock Movement
   │  ├─ Inventory Ledger
   │  └─ Slow Moving Inventory
   │
   ├─ Fixed Asset Reports
   │  ├─ Fixed Asset Register
   │  ├─ Depreciation Schedule
   │  ├─ Book vs Tax Depreciation
   │  └─ Asset Disposal Report
   │
   ├─ Management Reports
   │  ├─ Branch P&L
   │  ├─ Department Report
   │  ├─ Cost Center Report
   │  └─ Gross Margin Analysis
   │
   ├─ Transaction Registers
   │  ├─ Journal Register
   │  ├─ Sales Invoice Register
   │  ├─ Receipt Register
   │  ├─ Purchase Register
   │  ├─ Payment Register
   │  ├─ Credit Memo Register
   │  ├─ Debit Memo Register
   │  └─ Check Register
   │
   └─ Audit Reports
      ├─ Period Close Checklist
      ├─ Audit Support Package
      └─ User Activity Report
```

---

*End of UI/UX Principles & Navigation Architecture — Version 2.0*
*Maintained by: Principal Frontend Architect*
*This document supersedes all previous UI/UX guidance.*
