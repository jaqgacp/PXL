# PXL ERP: Supreme Engineering Constitution

As the definitive master reference for the PXL ERP architecture, this document serves as the absolute, unbreakable constitution for all human developers, UI/UX designers, and AI models contributing to the system. PXL ERP is a strictly BIR-compliant, multi-tenant, accounting-first enterprise application built on React and Supabase. 

Any code, schema, or UI design that violates the 27 principles below shall be classified as technical debt and immediately rejected.

---

## 1. Accounting First
**WHAT:** PXL ERP is not merely an operational tool; it is a financial system. Every operational transaction (Sales, Purchasing, Inventory, Treasury) must ultimately resolve into a mathematically perfect, double-entry journal posting mapping to the General Ledger (GL) and Sub-Ledgers (SL).
**WHY:** In the Philippines, the Bureau of Internal Revenue (BIR) audits are merciless. Disconnected operational data (e.g., an invoice that doesn't correctly hit accounts receivable and revenue) leads to tax penalties and failed Computerized Accounting System (CAS) accreditation.
**HOW:** The Supabase database architecture enforces Automated Account Determination. When a user selects an Item on an invoice, the UI never asks them to select a GL account. Instead, the backend automatically fetches the `revenue_account_id` or `expense_account_id` mapped to the Item Master Data. The backend script then validates that `Total Debits = Total Credits` before allowing any record to persist in the `journal_entries` and `journal_entry_lines` tables.

## 2. Philippine Compliance First
**WHAT:** The system provides native, built-in structural support for Philippine taxation and reporting rules (VAT, EWT, FWT, Form 2307, Form 2306, SLSP, and CAS Books of Accounts) without requiring third-party plugins or external workarounds.
**WHY:** Generic international ERPs fail in the Philippines because local taxation is uniquely complex (e.g., withholding taxes at source, specific VAT relief for PEZA). An ERP without native compliance is useless to a Philippine enterprise.
**HOW:** The compliance logic is embedded directly into the transactional schemas. The `tax_applicability_matrix` dictates visibility of reports (e.g., 2550Q, 1702Q). Transaction tables contain specific foreign keys for `ewt_code_id` and `atc_code` to calculate withholdings precisely. The `form_2307_registry` operates as a centralized clearinghouse bound by composite unique constraints to ensure no tax certificate is ever duplicated or missed.

## 3. Configuration over Customization
**WHAT:** The system must adapt to varying business processes through metadata toggles and settings rather than hardcoded logic or bespoke code branches. 
**WHY:** Hardcoding limits scalability. A Philippine enterprise might start as a Non-VAT Sole Proprietorship and grow into a VAT-registered Corporation. The system must adapt to this evolution instantly without developer intervention.
**HOW:** The `sys_feature_enablement` table acts as a global singleton. UI elements use React states tied to these booleans (e.g., `req_sales_flow = false`) to dynamically hide or show modules like Quotations or Purchase Requests. The logic remains centralized, allowing users to configure progressive disclosure strictly through the Setup UI.

## 4. Complete but not Overwhelming
**WHAT:** The UI must employ Progressive Disclosure. It should feel lightweight and intuitive for small businesses, yet seamlessly expand to reveal complex enterprise power tools when configured for large corporations.
**WHY:** User adoption fails when simple tasks (like issuing a cash receipt) require navigating a 50-field enterprise matrix. 
**HOW:** By leveraging cascading lookups and master data defaults, the UI minimizes manual entry. The frontend conditionally renders complex tabs (like "Landed Cost Allocations" or "EWT Schedules") only if those features are toggled `ON` in the `sys_feature_enablement` and `tax_applicability_matrix` tables.

## 5. Enterprise Architecture from Day One
**WHAT:** The database schema must be structurally designed to handle massive, multi-tenant loads and high transaction concurrency without requiring future redesigns or migrations.
**WHY:** Refactoring a flat database into a normalized, multi-tenant structure post-launch is catastrophic, expensive, and risks corrupting financial ledgers.
**HOW:** Every table strictly adheres to Header/Line-Item separation (e.g., `sales_invoices` and `sales_invoice_items`). Foreign keys always reference UUIDs, never integers or strings. Standard indexes are applied to high-traffic lookup columns, and massive data sets utilize lazy loading and server-side pagination.

## 6. Multi-Tenant Native
**WHAT:** The architecture enforces absolute hierarchical isolation across the organization: Company -> Branch -> Department -> Cost Center -> Project -> Employee.
**WHY:** Conglomerates and accounting firms manage multiple entities. Mixing data across companies is a fatal security flaw and a catastrophic accounting failure.
**HOW:** EVERY transactional and master data table requires a `company_id` column as a UUID foreign key. Furthermore, Supabase Row-Level Security (RLS) policies are written to strictly evaluate `auth.uid()` against the user's assigned `company_id`, making cross-tenant data mathematically invisible at the database level.

## 7. Every Transaction is Traceable
**WHAT:** The architecture must provide infinite drill-down capabilities. An auditor looking at the final Financial Statement must be able to click down to the GL, down to the Sub-Ledger, down to the source document, and down to the specific user/timestamp that created it.
**WHY:** BIR audits and internal forensic accounting require an unbroken chain of custody for every peso that moves through the system.
**HOW:** Transactions use polymorphic IDs or explicit foreign keys (e.g., `source_document_id`, `source_type`) in the `journal_entries` table to link the accounting impact back to the operational trigger (like a `sales_invoice_id`). This allows the UI to render a "GL Impact" tab on every transaction screen.

## 8. Immutable Accounting
**WHAT:** Once an accounting entry (Invoice, Bill, Payment, Journal Entry) is posted to the ledger, it cannot be edited or deleted under any circumstances. Mistakes must be corrected via strict Reversals, Credit Notes, or Debit Memos.
**WHY:** Deleting or altering posted transactions destroys the audit trail and is strictly prohibited under Philippine accounting standards and BIR CAS regulations.
**HOW:** Supabase RLS policies are configured to disable `UPDATE` and `DELETE` actions on rows where `status = 'Posted'`. The UI entirely removes the "Edit" and "Delete" buttons for posted records, replacing them with a "Void/Reverse" button that automatically generates a counter-entry journal posting.

## 9. Audit Everything
**WHAT:** The system requires a global, immutable tracking mechanism that captures Who, When, What Table, What Action, and the exact Before/After JSON states for every modification.
**WHY:** Trust is paramount. If a user maliciously alters a vendor's bank account before a payment run, the system must definitively prove who did it and what the value was changed from.
**HOW:** The `sys_audit_logs` table acts as the ultimate compliance tracker. It is an append-only architecture where RLS prevents even Administrators from deleting or updating rows. Database triggers automatically capture the `OLD` and `NEW` row states as `JSONB` payloads upon any `INSERT`, `UPDATE`, or `DELETE`.

## 10. Stable Before Fast
**WHAT:** Correctness, data integrity, and ledger consistency completely override the desire for rapid feature deployment or "moving fast and breaking things."
**WHY:** An ERP is the nervous system of a business. A bug in a social media app is an inconvenience; a bug in a tax calculation engine results in millions of pesos in BIR penalties.
**HOW:** New modules must achieve 100% test coverage for their underlying Supabase RPCs (Remote Procedure Calls) and mathematical logic before frontend integration. The schema strictly enforces constraints (`NOT NULL`, `DEFAULT`, `CHECK`) at the database level so the UI cannot physically submit corrupt data.

## 11. Low Maintenance
**WHAT:** The architecture must be designed so that standard business operations, fiscal year turnovers, and BIR tax rate updates require absolutely zero developer intervention.
**WHY:** Enterprises cannot afford to hire developers every time the BIR changes the EWT rate or when a new fiscal year starts. The system must be self-sustaining.
**HOW:** Tax rates (e.g., VAT 12%, ATC WC158 1%) are never hardcoded in the codebase. They are stored in `tax_codes` and `ewt_codes` tables. The `09. Accounting/Period End Closing` module contains the UI and backend logic to automatically lock periods and sweep Retained Earnings, entirely managed by the Financial Controller.

## 12. Metadata Driven
**WHAT:** Business logic (Tax codes, approval matrices, number series, workflows) must reside in relational database configuration tables, never hardcoded into the React frontend or backend functions.
**WHY:** Hardcoding forces recompilation and redeployment for simple operational changes, severely crippling agility.
**HOW:** Document numbering (e.g., "INV-2024-0001") is driven by a `document_sequences` table. Approvals are driven by a `role_permissions` matrix. When an admin updates a toggle via the Setup module UI, the system instantly alters its behavior without altering a single line of codebase code.

## 13. One Source of Truth
**WHAT:** Data duplication is banned. Centralized entity records must be referenced strictly via foreign key UUIDs across the entire platform.
**WHY:** If a Vendor's address is stored as plain text on a Purchase Order, updating the Vendor Master Data will not update historical records, creating fragmented, untrustworthy data.
**HOW:** Transaction tables (like `sales_invoices`) only store the `customer_id` UUID. The frontend always executes a `JOIN` to pull the live `address`, `tin`, and `tax_type` directly from the `customers` table, ensuring global synchronization.

## 14. Modular Architecture
**WHAT:** The system must maintain independent, clean, and distinct boundaries between its core pillars: Setup, Master Data, Sales, Purchasing, Inventory, Accounting, Compliance, and Reports.
**WHY:** Spaghetti architecture where Sales logic is heavily intertwined with Setup logic prevents scalability and makes debugging impossible.
**HOW:** Modules communicate strictly through defined interfaces and unified tables (like the GL). A change to the `04. Sales` UI does not affect `05. Purchasing`, because they rely independently on the shared `03. Master Data` and post independently to `09. Accounting`.

## 15. Reusable Components
**WHAT:** The frontend must utilize unified UI patterns for common actions (lookups, lists, forms, and approvals) to prevent spaghetti code and bloated repositories.
**WHY:** Building 50 different variations of a "Dropdown Linked to Customers" component creates massive technical debt and an inconsistent user experience.
**HOW:** The React frontend heavily utilizes centralized, generic components. A single `<MasterDataSelect module="customers" />` component handles fetching, caching, and auto-filling logic, reused across every Quotation, Order, and Invoice screen.

## 16. Consistent UX
**WHAT:** The user experience must be identical across all modules. Searching, filtering, pagination, table structures, and data entry behaviors must follow the exact same interaction design.
**WHY:** Users should not have to relearn how to filter data when moving from Inventory to Treasury. Consistency accelerates onboarding and reduces operational errors.
**HOW:** The Dashboard UI standard enforces a strict layout: Action Bar on top, Filters on the left/top, and Data List (Grid) in the center. Forms always follow the standard Header (top) and Line-Item Grid (bottom) layout.

## 17. Professional ERP UX
**WHAT:** The UI design must prioritize dense, fast, and keyboard-friendly data grids inspired by top-tier systems like NetSuite and SAP Business One. Oversized, "consumer-app" layouts with massive whitespace are banned.
**WHY:** Enterprise data encoders process hundreds of transactions a day. They need to see maximum data on screen and navigate rapidly using the `Tab` and `Enter` keys without touching a mouse.
**HOW:** Tables utilize condensed padding. Form inputs explicitly support keyboard navigation. Cascading lookups instantly populate secondary fields to minimize keystrokes, maximizing encoder efficiency.

## 18. Performance by Design
**WHAT:** The architecture must be explicitly designed for speed, regardless of database size. Server-side filtering, lazy loading, and paginated data fetching are mandatory.
**WHY:** Pulling an unpaginated list of 50,000 Sales Invoices will crash the browser and cripple the database. 
**HOW:** Supabase queries explicitly utilize `.range(from, to)` limits. Search bars trigger debounced RPC calls to the backend rather than filtering massive arrays on the client side. Dashboard widgets compute KPIs using materialized views rather than raw transactional queries.

## 19. Security First
**WHAT:** The system must enforce impenetrable security utilizing Supabase Row-Level Security (RLS), explicit Role-Based Access Control (RBAC) mapping, and multi-layered approval matrices.
**WHY:** ERPs contain highly sensitive financial, payroll, and corporate data. Unauthorized access or internal fraud can bankrupt a company.
**HOW:** The `role_permissions` table dictates exact CRUD rights (Create, Read, Update, Delete, Approve, Void). RLS policies read these permissions on every query. If a user's role lacks the `can_approve` boolean for the `Purchasing` module, the database will literally refuse the `UPDATE` command, even if the frontend button is somehow clicked.

## 20. Feature Completeness
**WHAT:** There are no placeholders. Before a module is declared "complete," it must possess 100% complete CRUD capabilities, strict mathematical validation, import/export functions, and integration with the audit logs.
**WHY:** Half-finished modules create broken data links and frustrate users, undermining trust in the ERP platform.
**HOW:** Strict checklists are applied to every blueprint. If a module like "Fixed Assets" cannot fully calculate depreciation, post to the GL, and track its audit history, it is rejected by the Lead Architect and sent back for refactoring.

## 21. AI-Assisted, Human-Controlled
**WHAT:** AI models are utilized to handle the mass generation of code and boilerplate schemas, but human architects ruthlessly govern the structural logic, tax compliance, and system constraints.
**WHY:** AI lacks the legal accountability and nuanced understanding of Philippine tax traps. The human architect provides the strategic boundary; the AI provides the tactical speed.
**HOW:** All AI outputs are audited against this `PXL_PRINCIPLES.md` document. If an AI suggests a flat table structure for a transaction, the human architect rejects it and commands adherence to the Header/Line-Item normalization rule.

## 22. Build the Foundation Once
**WHAT:** Core systemic mechanics—authentication, ledger posting rules, tax engines, and audit tracking—are sacred and unalterable once established. They must be built perfectly the first time.
**WHY:** Changing the core double-entry accounting engine halfway through development requires refactoring every single module in the ERP, resulting in catastrophic delays.
**HOW:** The foundational blueprints (`09. Accounting`, `02. Setup`) were established, reviewed, and locked down first. All operational modules (`Sales`, `Purchasing`, `Inventory`) are strictly built to inherit and feed into this unchangeable core.

## 23. Zero Technical Debt Policy
**WHAT:** If an architectural flaw, normalization error, or compliance gap is spotted, it must be refactored immediately. The concept of "we will fix it later" is permanently banned.
**WHY:** Technical debt in an ERP compounds exponentially. A flawed data type in a master table will replicate across millions of transactional line items, becoming practically impossible to fix in production.
**HOW:** The Lead Architect conducts ruthless directory-wide audits. If a missing boolean default or a missing UI component specificity is found, subagents are immediately deployed to rewrite the schemas before any frontend code is generated.

## 24. No Fake Data in Production Logic
**WHAT:** The production codebase must be strictly isolated from mock data or seed scripts. Operational logic cannot rely on hardcoded test values.
**WHY:** Hardcoded test data slipping into a production financial environment will corrupt actual company ledgers and cause massive compliance failures.
**HOW:** Seed data is maintained in entirely separate SQL migration files explicitly ignored by the production build process. The ERP logic relies entirely on the dynamic data pulled from the `sys_feature_enablement` and `Master Data` tables.

## 25. Every Module Must Be Production Ready
**WHAT:** A module is only finished if it includes full exception handling, unbreakable security boundaries, and local Philippine compliance natively built-in.
**WHY:** A module that works on the "happy path" but crashes when a user inputs a negative quantity on a Sales Order is not an enterprise module; it is a prototype.
**HOW:** Database schemas enforce strict `CHECK (amount >= 0)` constraints. Frontend components wrap inputs in strict validation schemas (e.g., Zod) to catch format errors before the API call is even made.

## 26. Build an Accounting Platform, Not Just an ERP
**WHAT:** The system must benchmark its performance, scalability, and controls against global giants like NetSuite and SAP, while remaining natively and flawlessly customized for Philippine regulations.
**WHY:** Philippine enterprises deserve world-class software that doesn't force them into expensive workarounds just to file their BIR 2307s or 2550Qs.
**HOW:** By leveraging Supabase's massive PostgreSQL scalability, React's dynamic UI rendering, and the strict adherence to this constitution, PXL ERP operates as a true platform—capable of handling millions of rows while providing millisecond responsiveness.

## 27. No Architectural Drift
**WHAT:** The established database patterns, naming conventions, and compliance rules documented in the blueprints strictly override any conflicting AI suggestions or developer shortcuts.
**WHY:** Architectural drift causes the codebase to become a fragmented mess of conflicting patterns, destroying maintainability.
**HOW:** This document, `PXL_PRINCIPLES.md`, acts as the ultimate prompt injection and context anchor for all future development. Any code generation must align with these 27 principles.

---

# PXL Vision Statement
**We are building the definitive financial nervous system for the Philippine Enterprise.** 

PXL ERP is not just a collection of forms; it is an impenetrable fortress of data integrity, engineered to empower businesses with progressive simplicity while fiercely protecting them from compliance failure. We reject technical debt. We enforce mathematical perfection. We automate the mundane so our users can focus on growth. Every line of code, every database constraint, and every UI component we deploy serves one singular mission: **To deliver world-class, globally-benchmarked enterprise architecture, perfectly natively tailored for the Philippines.** 

This is our Constitution. Execute flawlessly.
