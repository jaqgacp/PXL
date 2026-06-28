# PXL ERP — Lovable Prompt Templates

Copy the relevant template, fill in the `[BRACKETS]`, and paste into Lovable.
You do NOT need to modify anything else — the template handles all instructions.

---

## Template 1 — Start a New Build Step

Use this when beginning a step from BUILD_ORDER.md.

```
Read LOVABLE_GUIDE.md first. Do not read any other file yet.

Current build step: [S0.1 / S1.5 / S5.1 / etc. — copy from BUILD_ORDER.md]
Task: [paste the description from BUILD_ORDER.md]

After reading LOVABLE_GUIDE.md, read only the file(s) listed in the Reference Map 
for this step. Then build exactly what is described. Apply all Core Patterns from 
the guide. Follow all Supabase rules.

When complete, tell me: "Step [X] complete. Ready for [next step name]."
```

---

## Template 2 — Continue Previous Session

Use this when resuming work that wasn't finished in the last session.

```
Read LOVABLE_GUIDE.md first. Do not read any other file yet.

We are continuing step: [S0.3 / S1.5 / etc.]
What was done last session: [brief description of what was built]
What still needs to be done: [brief description of remaining work]

After reading LOVABLE_GUIDE.md, read only: [filename from Reference Map]
Continue from where we left off. Apply all Core Patterns from the guide.
```

---

## Template 3 — Build a Specific Screen (When You Know the File)

Use this when you want to build a specific module screen directly.

```
Read LOVABLE_GUIDE.md first. Do not read any other file yet.

Then read: [exact file path, e.g., "05. Purchasing/03. Transactions/03. Vendor Bills.md"]

Build the [list page / form page / both] for [module name].
Apply all Core Patterns from LOVABLE_GUIDE.md.
Follow all Supabase database rules from the guide.
Use the shared components already built (DataTable, StatusBadge, PageShell, etc.).
```

---

## Template 4 — Build Shared Components (Step S0.4)

Use this only once for the foundation components session.

```
Read LOVABLE_GUIDE.md first. Then read UI_UX_PRINCIPLES.md sections 3 through 7 only.

Build ALL shared components listed in LOVABLE_GUIDE.md under 
"Global Shared Components to Build First". These are:
PageShell, DataTable, StatusBadge, LookupDialog, FormSection, EmptyState, 
ConfirmDialog, AuditTrailSection, ContextBar, MegaMenu, AmountCell, DateCell.

These components will be reused by every module. Build them as generic, 
prop-driven components. Do not hardcode any module-specific logic into them.
Apply all Tailwind and Shadcn conventions from the guide.
```

---

## Template 5 — Fix a Bug or Issue

Use this when something isn't working correctly.

```
Read LOVABLE_GUIDE.md first. Do not read any blueprint files.

Bug in: [screen or component name]
What is happening: [describe the wrong behavior]
What should happen: [describe the correct behavior]

Fix only this issue. Do not refactor other parts of the code.
Keep all existing Core Patterns and Supabase rules intact.
```

---

## Template 6 — Add a Feature to an Existing Screen

Use this when adding something new to a screen already built.

```
Read LOVABLE_GUIDE.md first. Do not read any other file yet.

Existing screen: [screen name, e.g., Sales Invoices List]
Feature to add: [describe exactly what to add]

If you need the original blueprint for reference, read: [filename]
Otherwise, base the feature on the Core Patterns in LOVABLE_GUIDE.md.
Do not change anything else on the screen — only add what is described.
```

---

## Template 7 — Database Schema Creation (Supabase)

Use this when you need Supabase tables created for a module before building the UI.

```
Read LOVABLE_GUIDE.md first. Then read: [specific blueprint file]

Create the Supabase database tables for [module name] as specified in the blueprint.

Mandatory requirements from LOVABLE_GUIDE.md:
- All tables must have company_id with REFERENCES companies(id)
- RLS must be enabled on all tables with tenant isolation policy
- Composite unique constraints on (company_id, document_number)
- Audit columns: created_by, updated_by, created_at, updated_at
- Immutability policy blocking UPDATE when status = 'posted' or 'filed'
- No DELETE policy (USING false) on all transactional tables

Generate the SQL migration file first, then confirm before applying.
```

---

## Template 8 — Setup Auth (Step S0.1)

Use this only for the very first session.

```
Read LOVABLE_GUIDE.md first. Then read: 02. Setup/01. Organization/01. Company Setup.md

Set up the Supabase authentication for PXL ERP:

1. Configure Google OAuth in Supabase Auth (Gmail sign-in)
2. Configure Email + Password auth as secondary method
3. Create the users table with: id, email, full_name, avatar_url, is_active, created_at
4. Create a users_companies junction table: user_id, company_id, branch_id, role, is_active
5. Create a Supabase Edge Function that adds company_id, branch_id, and role as 
   custom claims to the JWT on login
6. Create the Zustand useAuthStore as specified in LOVABLE_GUIDE.md Auth section
7. Create the login page with: Google sign-in button (primary), email/password form 
   (secondary), PXL ERP logo, professional ERP styling (not consumer app)
8. Auth flow: after login → check users_companies → if no company → redirect to 
   Company Setup wizard → else → redirect to Dashboard

Apply all styling rules from LOVABLE_GUIDE.md Core Patterns.
```

---

## Template 9 — Navigation & App Shell (Step S0.3)

Use this for building the main app frame.

```
Read LOVABLE_GUIDE.md first. Read UI_UX_PRINCIPLES.md Section 2 (Layout & Navigation) only.

Build the PXL ERP application shell:

1. Fixed top navigation bar (h-14, fixed, z-50, border-b)
   - Left: PXL ERP logo + wordmark
   - Center: Mega Menu with these 11 top-level tabs:
     Dashboard | Setup | Master Data | Sales | Purchasing | Inventory | 
     Banking & Treasury | Fixed Assets | Accounting | Compliance | Reports
   - Right: Context Bar (Company/Branch/Period selectors) + User avatar menu
   
2. Mega menu behavior: hover on tab → dropdown panel appears → grid layout showing 
   sub-modules grouped by category (follow the navigation structure in UI_UX_PRINCIPLES.md 
   Section 8 exactly)

3. Global search (Ctrl+K) using Shadcn CommandDialog

4. Main content area: pt-14 to clear fixed nav, full height

5. PageShell component that all pages use

Use only Shadcn NavigationMenu + custom positioning for the mega menu.
Use Lucide icons only. Professional ERP styling — not consumer app.
```

---

## Template 10 — End of Session Checkpoint

Paste this at the END of any session to get a clean handoff summary.

```
Before we end this session:

1. List exactly what was built or changed this session (file names and component names)
2. List anything that is partially done and what remains
3. List any issues or limitations I should know about
4. Confirm the current build step status for LOVABLE_GUIDE.md 
   (should I mark this step as DONE?)
5. What is the exact next step?
```

---

## Quick Reference — Most Common File Paths

When you need to reference a file quickly without checking the full Reference Map:

```
Auth & Company:     02. Setup/01. Organization/01. Company Setup.md
Chart of Accounts:  02. Setup/04. Accounting Setup/03. Chart of Accounts.md
Tax Setup:          02. Setup/05. Tax Setup/ (all files)
Feature Flags:      02. Setup/02. System Controls/03. Feature Settings/00. Global Feature Enablement.md
Approvals:          02. Setup/02. System Controls/04. Approval Matrix/01. Unified Approval Workflow.md
Customers:          03. Master Data/01. Parties/01. Customers.md
Suppliers:          03. Master Data/01. Parties/02. Suppliers.md
Sales Invoices:     04. Sales/03. Transactions/04. Sales Invoices.md
Vendor Bills:       05. Purchasing/03. Transactions/03. Vendor Bills.md
Petty Cash:         07. Banking & Treasury/01. Petty Cash/02. Petty Cash Vouchers.md
Check Vouchers:     07. Banking & Treasury/03. Payables/01. Check Vouchers.md
Asset Register:     08. Fixed Assets/01. Operations/02. Asset Register.md
Journal Entries:    09. Accounting/01. Journal Entries/01. Journal Entries.md
GL Entries:         09. Accounting/01. Journal Entries/00. General Ledger Entries.md
VAT 2550M:          10. Compliance/02. VAT/06. VAT Return 2550M.md
VAT 2550Q:          10. Compliance/02. VAT/07. VAT Return 2550Q.md
2307 Issued:        10. Compliance/03. Withholding Tax/10. 2307 Certificates Issued.md
2306 FWT:           10. Compliance/03. Withholding Tax/12. 2306 Certificates.md
UI Principles:      UI_UX_PRINCIPLES.md
```

---

*PXL ERP — Prompt Templates v2.0 | Updated: 2026-06-28*
