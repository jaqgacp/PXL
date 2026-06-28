# PXL ERP Blueprint: Executive Dashboard

## Module Overview
The Executive Dashboard serves as the central command center for business owners and executives. In the context of Philippine business practices, it consolidates real-time financial, operational, and tax compliance data into a highly visual interface. By seamlessly pulling Key Performance Indicators (KPIs) from across the ERP—such as Daily Cash Position, Outstanding Receivables, Input vs. Output VAT Estimates, and Monthly Revenue Trends—decision-makers can proactively monitor the financial health of the company. It ensures strict oversight over critical cash flow movements and pending BIR tax obligations without requiring executives to generate complex, granular reports manually.

## Dashboard UI
When users access the "Executive Dashboard" module, they will be presented with a customizable, widget-based workspace.

### The Action Bar
* **Global Date Range:** A date picker to filter the entire dashboard data (e.g., Today, This Month, Year-to-Date).
* **Entity Selector:** A dropdown allowing executives to view consolidated metrics for the parent company or drill down into specific subsidiaries/branches.
* **Refresh Button:** Forces a real-time recalculation of all visible KPIs and charts.
* **Customize Layout:** Toggles the dashboard into "Edit Mode," enabling drag-and-drop functionality to rearrange, add, or resize KPI widgets.
* **Export Button:** Downloads the current dashboard view as a highly visual PDF summary or exports the underlying KPI data to Excel/CSV for external analysis.
* **Import Button:** Allows the uploading of external data via CSV (such as industry benchmarks, historical targets, or legacy system KPIs) to overlay and compare against real-time actuals.

### The Data List (Widget Grid & Tabular Views)
Instead of a single traditional table, the Data List is divided into two primary sections:
1. **KPI Widget Grid:** A highly visual layout of cards containing Bar Charts, Line Graphs, and Summary Numbers. Standard widgets include:
   * **Cash Flow Overview:** Current cash balance across all registered banks.
   * **Receivables & Payables Aging:** 30/60/90+ day summaries.
   * **Tax Compliance Snapshot:** Estimated upcoming VAT and Withholding Tax liabilities.
   * **Revenue Trends:** Month-over-month gross sales comparisons.
2. **Recent Critical Activities (Tabular List):** A list of urgent items requiring executive attention, such as large pending purchase order approvals, overdue high-value invoices, or upcoming tax remittance deadlines. Columns include Date, Document Type, Reference, Amount, and Action required.

---

## Data Fields (Header & Line Items)
To support the customizable nature of the Executive Dashboard, the system stores "Dashboard Layouts" as headers and "Dashboard Widgets" as the associated line items. This allows different user roles to maintain their own personalized visual configurations.

### Section 1: Dashboard Configuration (Header)
| Field Name | UI Component | Description | Required? | Data Inheritance |
| :--- | :--- | :--- | :--- | :--- |
| Layout Name | Text Input | The descriptive title of the dashboard layout (e.g., "CEO Daily View", "Sales Manager KPIs"). | Yes | None |
| Target Role | Dropdown | The specific system role this layout is optimized for. | Yes | Auto-filled from System Roles |
| Default Date Filter | Dropdown | The default period applied when the dashboard loads (e.g., Current Month, Quarter-to-Date). | Yes | None |
| Is Default View | Checkbox | Determines if this layout is the primary view loaded upon user login. | Yes | None |
| Description | Text Area | Brief notes explaining the purpose of this dashboard layout. | Optional | None |

### Section 2: Dashboard Widgets (Line Items)
| Field Name | UI Component | Description | Required? | Data Inheritance |
| :--- | :--- | :--- | :--- | :--- |
| Widget Type | Dropdown | The visualization format (e.g., Summary Card, Pie Chart, Bar Chart, Data Table). | Yes | None |
| KPI Source | Dropdown | The specific system metric to query (e.g., `total_revenue`, `ar_aging`, `vat_payable`). | Yes | Sourced from Core System Metrics |
| Grid Position X | Read-only computed field | The horizontal coordinate on the layout grid. | Yes | Auto-computed via drag-and-drop |
| Grid Position Y | Read-only computed field | The vertical coordinate on the layout grid. | Yes | Auto-computed via drag-and-drop |
| Grid Width | Read-only computed field | The span of the widget horizontally across columns. | Yes | Auto-computed via resizing |
| Grid Height | Read-only computed field | The span of the widget vertically across rows. | Yes | Auto-computed via resizing |
| Custom Filter | JSON Builder | Advanced filtering rules specific to this widget (e.g., filtering sales by specific regions). | Optional | None |

---

## Supabase Database Architecture

The data structure is designed to persist user-defined dashboard configurations.

### Table 1: `dashboard_layouts` (Header Table)
**Critical Database Rule:** The `dashboard_layouts` table must have a composite unique constraint on (`layout_name`, `created_by`) to ensure a user does not create duplicate layout names.

Stores the overarching configuration for a specific dashboard view.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the dashboard layout. |
| `layout_name` | Text | Required, Unique | The name of the dashboard layout. |
| `target_role` | Text | Required | The user role this dashboard is intended for. |
| `default_date_filter` | Text | Required | Default period string (e.g., `current_month`). |
| `is_default_view` | Boolean | Default: `false` | Marks if this is the default layout. |
| `description` | Text | Nullable | Additional context or instructions. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. User who created the layout. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. User who last updated the layout. |
| `created_at` | Timestamp | Auto | Date and time the record was created. |
| `updated_at` | Timestamp | Auto | Date and time the record was last edited. |

### Table 2: `dashboard_widgets` (Line-Item Table)
Stores the individual charts, cards, and tables that belong to a specific dashboard layout.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the widget instance. |
| `dashboard_layout_id` | UUID | Required, Foreign Key | Links to `dashboard_layouts.id`. |
| `widget_type` | Text | Required | Type of visualization (e.g., `bar_chart`, `summary_card`). |
| `kpi_source` | Text | Required | Identifier for the backend data query to run. |
| `grid_pos_x` | Integer | Required | X-axis coordinate on the UI grid. |
| `grid_pos_y` | Integer | Required | Y-axis coordinate on the UI grid. |
| `grid_width` | Integer | Required | Number of columns the widget spans. |
| `grid_height` | Integer | Required | Number of rows the widget spans. |
| `custom_filter_json` | JSONB | Nullable | Any widget-specific overrides or parameters. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. User who added the widget. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. User who last modified the widget. |
| `created_at` | Timestamp | Auto | Date and time the widget was added. |
| `updated_at` | Timestamp | Auto | Date and time the widget was last edited. |
