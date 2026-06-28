# PXL ERP — Build Order & Progress Tracker

> Mark each step `✅ DONE` when complete. 
> Dependencies are listed — never skip ahead of them.

---

## SPRINT 0 — Foundation (No dependencies. Build first.)

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S0.1 | Supabase + Auth Setup | Supabase project, Google OAuth, email auth, users table, JWT custom claims edge function | ⬜ |
| S0.2 | Login Page | Login screen with Google button + email/password form. Handles first-time setup redirect. | ⬜ |
| S0.3 | App Shell | Fixed top nav bar, mega menu (all 11 module tabs), `<PageShell>` layout, breadcrumbs, context bar (Company/Branch/Period selector) | ⬜ |
| S0.4 | Shared Component Library | 

**Dependency:** Nothing. These are the foundation.

---

## SPRINT 1 — Setup Module: Core Configuration

> Dependencies: S0.1–S0.4 must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S1.1 | Company Setup | CRUD for companies. Name, TIN, address, RDO, CAS registration. This is the root of all multi-tenancy. | ⬜ |
| S1.2 | Branch Setup | CRUD for branches under a company. Branch code, name, address, is_head_office flag. | ⬜ |
| S1.3 | Department + Cost Centers | Department CRUD. Cost center CRUD. Both linked to company_id. | ⬜ |
| S1.4 | Fiscal Years + Calendar | Fiscal year creation (start/end month). Auto-generates 12 fiscal periods. Period lock/unlock controls. | ⬜ |
| S1.5 | Chart of Accounts | Account code, name, type (Asset/Liability/Equity/Revenue/Expense), is_control_account flag, parent account (for hierarchy). Import from template. | ⬜ |
| S1.6 | Currency Setup + Exchange Rates | Base currency (PHP default). Foreign currency setup. Daily exchange rate entry. | ⬜ |
| S1.7 | Global Feature Enablement | Toggle grid for all module features (fixed assets, multi-currency, VAT, etc.). Drives menu visibility. | ⬜ |
| S1.8 | Number Series | Four sub-modules: Sales, Purchasing, Accounting, Compliance documents. Prefix + starting number + padding. | ⬜ |
| S1.9 | Unified Approval Workflow | Build the approval_workflows + approval_workflow_steps tables and UI. Module type dropdown drives document type options. | ⬜ |
| S1.10 | System Audit Log | Read-only list view of sys_audit_logs. Filter by table, user, date range, action type. | ⬜ |

**Dependency:** S1.5 (Chart of Accounts) must exist before S1.4 (GL Posting Config), S5.1 (Sales Invoices), S6.1 (Vendor Bills), S9.1 (Journal Entries), and any module that posts to GL.

---

## SPRINT 2 — Setup Module: Tax & Compliance Configuration

> Dependencies: S1.1, S1.2 must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S2.1 | Tax Code Setup | VAT Codes (12%, 0%, exempt). EWT Codes (by ATC). FWT Codes. Percentage Tax Codes. ATC Code master list (pre-seeded). | ⬜ |
| S2.2 | Compliance Profile | Per-company BIR registration flags: vat_registered, ewt_registered, fwt_registered, efps_enrolled, efps_group, slsp_required, relief_required. | ⬜ |
| S2.3 | Tax Calendar | Read-only calendar view + list view of tax_calendar_events. Auto-generated from compliance profile. Color coding: red=overdue, amber=due soon, green=filed. | ⬜ |
| S2.4 | BIR Form Configuration | Setup of BIR form parameters per company (RDO code, form variant, filing frequency). | ⬜ |

---

## SPRINT 3 — Master Data

> Dependencies: S1.1, S1.2, S1.5 must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S3.1 | Customers | Full customer master: registered name, TIN, address, tax type, payment terms, AR control account, credit limit, contact persons. | ⬜ |
| S3.2 | Suppliers | Full supplier master: registered name, TIN, address, default EWT ATC code, AP control account, payment terms. | ⬜ |
| S3.3 | Items + Services + Categories + UoM | Item categories, units of measure, item master (with inventory and non-inventory types), services master. | ⬜ |
| S3.4 | Warehouses + Payment Terms | Warehouse master with location. Payment terms (net days, installment schedules). | ⬜ |

---

## SPRINT 4 — Dashboard

> Dependencies: S1.1–S1.4, S3.1–S3.2 must be complete (so widgets have real data to show).

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S4.1 | Dashboard | Workspace-based dashboard. Widgets: Pending Approvals, Unposted Transactions, Overdue AR, Cash Position, Tax Deadlines (from tax_calendar_events), Today's Tasks. Role-based widget sets. | ⬜ |

---

## SPRINT 5 — Sales Module

> Dependencies: S1.5, S2.1, S3.1, S3.3 must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S5.1 | Sales Invoices | The core sales document. Header + line items + VAT computation + GL posting preview. List + form. Status workflow: draft → for_approval → approved → posted. | ⬜ |
| S5.2 | Receipts (Customer Payments) | Link to open Sales Invoices. Apply payment. Partial payment support. GL: Dr Bank / Cr AR. | ⬜ |
| S5.3 | Credit Memos + Debit Memos | Credit/debit adjustments to customers. Link to original invoice. | ⬜ |
| S5.4 | Sales Orders + Quotations | Pre-invoice documents. Quotation → Sales Order conversion. Sales Order → Invoice conversion. | ⬜ |
| S5.5 | Delivery Receipts + Customer Returns | Delivery against Sales Order. Return processing with restocking. | ⬜ |
| S5.6 | AR Aging + Customer Ledger | AR Aging report (current, 30, 60, 90, 120+ days buckets). Customer ledger with running balance. | ⬜ |
| S5.7 | Sales Tax Review | Output VAT summary by period. 2307 Received tracking list. | ⬜ |
| S5.8 | Sales Registers | Sales Invoice Register, Receipt Register, Credit/Debit Memo Register, SLS (Summary List of Sales). | ⬜ |

---

## SPRINT 6 — Purchasing Module

> Dependencies: S1.5, S2.1, S3.2, S3.3 must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S6.1 | Vendor Bills (Purchase Invoices) | Core AP document. Header + lines + Input VAT + EWT computation. GL: Dr Expense/Asset / Cr AP. | ⬜ |
| S6.2 | Purchase Orders + Receiving Reports | PO creation. 3-way matching: PO → RR → Vendor Bill. | ⬜ |
| S6.3 | Payment Vouchers | AP payment against open Vendor Bills. Link to bank account. | ⬜ |
| S6.4 | Vendor Credits + Debit Memos | Supplier credit notes and debit adjustments. | ⬜ |
| S6.5 | AP Aging + Supplier Ledger | AP Aging report. Supplier ledger with running balance. | ⬜ |
| S6.6 | Purchasing Tax Review | Input VAT summary. EWT Summary by ATC code. 2307 Issued tracking. | ⬜ |
| S6.7 | Purchase Registers | Vendor Bill Register, Payment Register, Debit Memo Register, SLP. | ⬜ |

---

## SPRINT 7 — Banking & Treasury Module

> Dependencies: S1.1, S1.2, S1.5, S3.2 must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S7.1 | Petty Cash Fund + Vouchers | PCF setup (fund amount, custodian, GL account). PCV with expense lines, VAT computation. GL posts on approval. | ⬜ |
| S7.2 | Petty Cash Replenishment | Batch replenishment of PCVs. GL: Dr PCF / Cr Bank. | ⬜ |
| S7.3 | Fund Transfers | Inter-bank transfers within same company. GL: Dr Destination Bank / Cr Source Bank. | ⬜ |
| S7.4 | Inter-Branch Transfers | Transfers between branches. Due To/From GL accounts. | ⬜ |
| S7.5 | Bank Adjustments | Debit/Credit memos from bank. Interest income with 20% FWT split. | ⬜ |
| S7.6 | Bank Reconciliation | Match bank statement items to GL. Outstanding checks list. Deposits in transit. | ⬜ |
| S7.7 | Check Vouchers | AP payments via check. EWT deduction per ATC. Auto-generates 2307. GL: Dr AP / Cr EWT Payable / Cr Bank. | ⬜ |

---

## SPRINT 8 — Fixed Assets Module

> Dependencies: S1.5, S3.1 (for vendors) must be complete.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S8.1 | Asset Categories + Depreciation Profiles | Asset category master with capitalization threshold and GL accounts. Depreciation profile (SL, DB, etc.). | ⬜ |
| S8.2 | Asset Register | Master list of all fixed assets. net_book_value is computed (GENERATED ALWAYS AS — read-only field). | ⬜ |
| S8.3 | Asset Acquisition | Acquire assets against PO/AP Bill or manual. GL: Dr Asset Account / Cr AP. | ⬜ |
| S8.4 | Depreciation Run | Monthly/annual batch depreciation. GL: Dr Dep Expense / Cr Accumulated Dep. Updates asset_register.accumulated_depreciation. | ⬜ |
| S8.5 | Disposal + Transfer + Impairment | Asset disposal with gain/loss GL. Intra-branch and inter-entity transfers. Impairment loss posting. | ⬜ |

---

## SPRINT 9 — Accounting Module

> Dependencies: S1.4, S1.5 must be complete. All transaction modules (Sales, Purchasing, Banking) ideally complete first so GL has real data.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S9.1 | Journal Entries | Manual journal entry form. Header + Dr/Cr lines. Balance validation (Dr = Cr before posting). GL Posting Preview tab. | ⬜ |
| S9.2 | General Ledger Entries | Read-only GL inquiry. Filter by account, date range, branch, contact. Running balance column. Drill-down to source document. | ⬜ |
| S9.3 | General Ledger + Trial Balance | Account detail ledger view. Trial Balance report (unadjusted / adjusted / post-closing). | ⬜ |
| S9.4 | Control Account Reconciliation | Computed dashboard. GL balance vs subledger total. Variance flagging. Orphan entry drill-down. | ⬜ |
| S9.5 | Amortization Schedules | Create amortization schedule. Auto-generates period lines. Monthly run posts JE. | ⬜ |
| S9.6 | Period Management | Period Closing workflow. Fiscal lock controls. Posting Review, Reversal Review. Amortization Run, Revenue Recognition Run, Auto Reversal Run. | ⬜ |

---

## SPRINT 10 — Compliance Module

> Dependencies: S5.1 (Sales Invoices), S6.1 (Vendor Bills), S7.5 (Bank Adjustments), S9.1 (Journal Entries) must be complete and have posted data.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S10.1 | VAT Returns 2550M + 2550Q | Monthly and quarterly VAT returns. Auto-populated from posted SIs and PIs. BIR box mapping (Box 12–29). Amendment support. | ⬜ |
| S10.2 | SLSP + RELIEF Export | Summary list of sales and purchases. RELIEF export. Both generate BIR-compliant DAT files with all mandatory columns. | ⬜ |
| S10.3 | EWT Returns (0619-E, 1601EQ, QAP) | Monthly EWT remittance. Quarterly EWT return. Quarterly Alphalist of Payees. | ⬜ |
| S10.4 | 2307 Certificates (Issued + Received) | 2307 list management. PDF generation. Status: pending → issued. | ⬜ |
| S10.5 | 2306 Certificates | FWT certificates. Auto-created from Bank Adjustments (interest income). PDF generation. | ⬜ |
| S10.6 | BIR Books | General Journal, General Ledger Book, Cash Receipts Book, Cash Disbursements Book, Sales Journal, Purchase Journal, and subsidiary ledger books. | ⬜ |
| S10.7 | Income Tax | 1702Q and 1702RT forms. Taxable income computation. Book-to-tax reconciliation. MCIT computation. | ⬜ |
| S10.8 | Audit & CAS | CAS Dashboard. Transaction Audit Log (from sys_audit_logs). Master Data Change Log. DAT File Generation. Export History. | ⬜ |

---

## SPRINT 11 — Reports Module

> Dependencies: All transaction modules must be complete and have data.

| # | Step | Description | Status |
| :--- | :--- | :--- | :--- |
| S11.1 | Financial Statements | Balance Sheet, Income Statement, Statement of Cash Flows, Statement of Changes in Equity. Comparative view. | ⬜ |
| S11.2 | Trial Balance Reports | Unadjusted, Adjusted, Post-Closing. Export to Excel. | ⬜ |
| S11.3 | Tax Reports | Output/Input VAT Summary, EWT/FWT Summary, 2307 Issued/Received Listing. | ⬜ |
| S11.4 | Operational Reports | AR/AP Aging, Bank Position, Bank Reconciliation Summary, Inventory Valuation, Stock Movement, Fixed Asset Register, Depreciation Schedule. | ⬜ |
| S11.5 | Management + Audit Reports | Branch P&L, Department Report, Cost Center Report, Gross Margin, Transaction Registers, Period Close Checklist, Audit Support Package. | ⬜ |

---

## Dependency Summary

```
S0.1–S0.4  (Foundation)
    ↓
S1.1–S1.10 (Setup Core)     ← Required by EVERYTHING below
    ↓
S2.1–S2.4  (Tax Setup)      ← Required by S5, S6, S10
    ↓
S3.1–S3.4  (Master Data)    ← Required by S5, S6, S7, S8
    ↓
S4.1       (Dashboard)      ← Reads from all modules
    ↓
S5.1–S5.8  (Sales)          ← S9 + S10 depend on Sales data
S6.1–S6.7  (Purchasing)     ← S9 + S10 depend on Purchasing data
S7.1–S7.7  (Banking)        ← S9 + S10 depend on Banking data
S8.1–S8.5  (Fixed Assets)   ← S9 + S10 depend on Asset data
    ↓
S9.1–S9.6  (Accounting)     ← Requires all transaction data
    ↓
S10.1–S10.8 (Compliance)    ← Requires all posted data
    ↓
S11.1–S11.5 (Reports)       ← Requires everything
```

---

*PXL ERP — Build Order v2.0 | Updated: 2026-06-28*
*Total Steps: 50 | Completed: 0*
