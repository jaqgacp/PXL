# PXL ERP — Build Status

Last updated: 2026-06-30
Build: ✅ Clean (zero TS errors)
Migrations applied to Supabase: 001–027
Migrations pending (written, not yet pushed): none

---

## Legend
- ✅ Built & committed
- ⏳ Written but not yet applied (migrations)
- ❌ Not yet built

---

## Infrastructure
| Item | Status |
|---|---|
| Google OAuth + email/password login | ✅ |
| App shell — mega-menu, context bar (Company/Branch/Period), breadcrumbs | ✅ |
| Shared UI library (DataTable, StatusBadge, LookupDialog, FormSection, AmountCell, DateCell, ConfirmDialog, AuditTrailSection) | ✅ |
| Error boundary | ✅ |
| Lazy-loaded routing — all 71 pages | ✅ |

---

## Migrations

| File | Description | Applied |
|---|---|---|
| 20260628000001_companies.sql | Companies, RDO codes | ✅ |
| 20260628000002_sprint1.sql | Setup module schema | ✅ |
| 20260628000003_sprint2.sql | Master data schema | ✅ |
| 20260628000004_fixes.sql | Schema fixes | ✅ |
| 20260628000005_sprint2_tax.sql | Tax setup schema | ✅ |
| 20260629000001_dashboard.sql | Dashboard views | ✅ |
| 20260629000002_sprint5_sales.sql | Sales invoices, void reason codes | ✅ |
| 20260629000003_sprint5_ar.sql | Receipts, CMs, DMs, ref tables | ✅ |
| 20260629000004_sprint5_so_dr.sql | Quotations, SOs, Delivery Receipts | ✅ |
| 20260629000005_sprint5_views.sql | AR/Sales reporting views | ✅ |
| 20260629000006_ewt_working_papers.sql | EWT working papers | ✅ |
| 20260629000007_cwt_2307.sql | CWT/2307 compliance | ✅ |
| 20260629000008_rls_hardening.sql | RLS security hardening | ✅ |
| 20260629000009_rls_reads_scope.sql | RLS read scope fixes | ✅ |
| 20260629000010_posting_rpcs.sql | Atomic posting RPCs | ✅ |
| 20260629000011_audit_triggers.sql | Audit trail triggers | ✅ |
| 20260629000012_fn_numbering_hardening.sql | Number series hardening | ✅ |
| 20260629000013_gl_core.sql | GL core schema + journal_entries | ✅ |
| 20260629000014_hardening.sql | Accounting hardening | ✅ |
| 20260629000015_cm_dm_rpcs.sql | CM/DM RPC functions | ✅ |
| 20260629000016_cash_sales.sql | Cash sales schema | ✅ |
| 20260629000017_purchasing.sql | Purchasing schema (initial) | ✅ |
| 20260629000018_purchasing_full.sql | Purchasing schema (full) | ✅ |
| 20260629000019_hardening_v2.sql | C1 integrity hardening | ✅ |
| 20260629000020_period_enforcement_ar.sql | Period enforcement for AR | ✅ |
| 20260629000021_cm_dm_gl_pv_void_vc_apply.sql | CM/DM GL wiring, PV void, vendor credit apply | ✅ |
| 20260630000021_gap_fill.sql | Idempotent catch-up migration (content of 008–021) | ✅ |
| 20260630000022_tax_ledger_completeness.sql | VAT breakdowns, form_2307_issuance_lines, rebased EWT views | ✅ |
| 20260630000023_banking_treasury_schema.sql | Banking & Treasury — 12 tables, RLS | ✅ |
| 20260630000024_banking_treasury_functions.sql | Banking & Treasury — posting functions, views | ✅ |
| 20260630000025_accounting_module.sql | Accounting — recurring templates, GL views, posting functions | ✅ |
| 20260630000026_amortization_revenuerecon.sql | Amortization & Revenue Recognition schedule tables, RLS, posting functions | ✅ |
| 20260630000027_fixed_assets.sql | Fixed Assets — 6 tables, schedule generator, 5 posting RPCs | ✅ |

---

## Setup Module
| Page | File | Status |
|---|---|---|
| Company Setup | CompanySetupPage.tsx | ✅ |
| Branch Setup | BranchSetupPage.tsx | ✅ |
| Departments & Cost Centers | DepartmentSetupPage.tsx | ✅ |
| Fiscal Years & Calendar | FiscalYearsPage.tsx | ✅ |
| Chart of Accounts | ChartOfAccountsPage.tsx | ✅ |
| Currency Setup | CurrencySetupPage.tsx | ✅ |
| Feature Enablement | FeatureEnablementPage.tsx | ✅ |
| Number Series | NumberSeriesPage.tsx | ✅ |
| Approval Workflows | ApprovalWorkflowPage.tsx | ✅ |
| System Audit Log | AuditLogPage.tsx | ✅ |
| Petty Cash Fund Setup | PettyCashFundSetupPage.tsx | ✅ |

## Tax & Compliance Setup
| Page | File | Status |
|---|---|---|
| Tax Code Setup | TaxSetupPage.tsx | ✅ |
| Compliance Profile | ComplianceProfilePage.tsx | ✅ |
| Tax Calendar | TaxCalendarPage.tsx | ✅ |
| BIR Form Configuration | BIRFormConfigPage.tsx | ✅ |

## Master Data
| Page | File | Status |
|---|---|---|
| Customers | CustomersPage.tsx | ✅ |
| Suppliers | SuppliersPage.tsx | ✅ |
| Item Catalog (Items / Services / Categories / UoM) | ItemCatalogPage.tsx | ✅ |
| Payment Terms | PaymentTermsPage.tsx | ✅ |
| Bank Accounts | BankAccountsPage.tsx | ✅ |
| Warehouses | — | ❌ |
| Warehouse Stock Settings | — | ❌ |
| Personnel / Employees Lite | — | ❌ |

## Dashboard
| Page | File | Status |
|---|---|---|
| Executive Dashboard | DashboardPage.tsx | ✅ |

---

## Sales / AR Module
| Page | File | Status |
|---|---|---|
| Quotations | QuotationsPage.tsx | ✅ |
| Sales Orders | SalesOrdersPage.tsx | ✅ |
| Delivery Receipts | DeliveryReceiptsPage.tsx | ✅ |
| Sales Invoices | SalesInvoicePage.tsx | ✅ |
| Cash Sales | CashSalesPage.tsx | ✅ |
| Receipts (Official Receipts) | ReceiptsPage.tsx | ✅ |
| Credit Memos | CreditMemosPage.tsx | ✅ |
| Debit Memos | DebitMemosPage.tsx | ✅ |
| Customer Returns | CustomerReturnsPage.tsx | ✅ |
| AR Aging & Customer Ledger | ARAgingPage.tsx | ✅ |
| Collection Monitoring | CollectionMonitoringPage.tsx | ✅ |
| Output VAT Review | SalesTaxReviewPage.tsx | ✅ |
| Percentage Tax Review | PercentageTaxReviewPage.tsx | ✅ |
| 2307 Received Review | Form2307ReceivedPage.tsx | ✅ |
| Sales Registers (SI / OR / CM / DM) | SalesRegistersPage.tsx | ✅ |
| Summary List of Sales (SLS) | SLSPage.tsx | ✅ |

---

## Purchasing / AP Module
| Page | File | Status |
|---|---|---|
| Purchase Orders | PurchaseOrdersPage.tsx | ✅ |
| Receiving Reports | ReceivingReportsPage.tsx | ✅ |
| Vendor Bills | VendorBillsPage.tsx | ✅ |
| Cash Purchases | CashPurchasesPage.tsx | ✅ |
| Payment Vouchers | PaymentVouchersPage.tsx | ✅ |
| Vendor Credits | VendorCreditsPage.tsx | ✅ |
| Debit Memos to Suppliers | SupplierDebitMemosPage.tsx | ✅ |
| Purchase Returns | PurchaseReturnsPage.tsx | ✅ |
| AP Aging & Supplier Ledger | APAgingPage.tsx | ✅ |
| Payment Monitoring | PaymentMonitoringPage.tsx | ✅ |
| Input VAT Review | InputVATReviewPage.tsx | ✅ |
| EWT Summary | EWTSummaryPage.tsx | ✅ |
| 2307 Issued Review | Form2307IssuedPage.tsx | ✅ |
| Purchase Registers (VB / PV / SDM / SLP) | PurchaseRegistersPage.tsx | ✅ |

---

## Inventory Module
| Page | File | Status |
|---|---|---|
| Inventory Dashboard | — | ❌ |
| Stock Adjustment | — | ❌ |
| Stock Transfer | — | ❌ |
| Goods Issue | — | ❌ |
| Physical Count | — | ❌ |
| Inventory Movements | — | ❌ |
| Inventory Valuation | — | ❌ |

---

## Banking & Treasury Module
| Page | File | Status |
|---|---|---|
| Petty Cash Vouchers | PettyCashVouchersPage.tsx | ✅ |
| Petty Cash Replenishment | PettyCashReplenishmentPage.tsx | ✅ |
| Cash Count Sheet | CashCountSheetPage.tsx | ✅ |
| Fund Transfers | FundTransfersPage.tsx | ✅ |
| Inter-Branch Transfers | InterBranchTransfersPage.tsx | ✅ |
| Bank Adjustments | BankAdjustmentsPage.tsx | ✅ |
| Bank Reconciliation | BankReconciliationPage.tsx | ✅ |
| Outstanding Checks | OutstandingChecksPage.tsx | ✅ |
| Deposits in Transit | DepositsInTransitPage.tsx | ✅ |
| Check Vouchers | CheckVouchersPage.tsx | ✅ |

---

## Fixed Assets Module (S11 — PAS 16 / PAS 36)
| Page | File | Status |
|---|---|---|
| Fixed Asset Dashboard | FixedAssetDashboardPage.tsx | ✅ |
| Asset Register | AssetRegisterPage.tsx | ✅ |
| Asset Acquisition | AssetAcquisitionPage.tsx | ✅ |
| Depreciation Run | DepreciationRunPage.tsx | ✅ |
| Asset Disposal | AssetDisposalPage.tsx | ✅ |
| Asset Transfer | AssetTransferPage.tsx | ✅ |
| Asset Impairment (PAS 36) | AssetImpairmentPage.tsx | ✅ |
| Asset Categories (Setup) | AssetCategoriesPage.tsx | ✅ |

---

## Accounting Module
| Page | File | Status |
|---|---|---|
| GL Posting Configuration | GLPostingConfigPage.tsx | ✅ |
| Journal Entries (manual JE + reverse) | JournalEntriesPage.tsx | ✅ |
| Recurring Journal Templates | RecurringJournalTemplatesPage.tsx | ✅ |
| General Ledger | GeneralLedgerPage.tsx | ✅ |
| Account Detail Ledger | AccountDetailLedgerPage.tsx | ✅ |
| Trial Balance | TrialBalancePage.tsx | ✅ |
| Period Closing & Fiscal Locks | PeriodClosingPage.tsx | ✅ |
| Posting Review | PostingReviewPage.tsx | ✅ |
| Reversal Review | ReversalReviewPage.tsx | ✅ |
| Control Account Reconciliation | ControlAccountReconciliationPage.tsx | ✅ |
| Amortization Schedules | AmortizationSchedulesPage.tsx | ✅ |
| Revenue Recognition Schedules | RevenueRecognitionSchedulesPage.tsx | ✅ |
| Amortization Run | AmortizationRunPage.tsx | ✅ |
| Revenue Recognition Run | RevenueRecognitionRunPage.tsx | ✅ |
| Auto Reversal Run | AutoReversalRunPage.tsx | ✅ |

---

## Compliance Module
| Page | File | Status |
|---|---|---|
| EWT Working Papers | EWTWorkingPapersPage.tsx | ✅ |
| 2307 Certificates Issued | Form2307IssuedPage.tsx | ✅ |
| 2307 Certificates Received | Form2307ReceivedPage.tsx | ✅ |
| PT Dashboard | — | ❌ |
| PT Working Papers | — | ❌ |
| PT Quarterly Return (2551Q) | — | ❌ |
| PT Reconciliation | — | ❌ |
| PT Summary Register | — | ❌ |
| VAT Dashboard | — | ❌ |
| VAT Working Papers | — | ❌ |
| Output VAT Summary | — | ❌ |
| Input VAT Summary | — | ❌ |
| VAT Reconciliation | — | ❌ |
| VAT Return 2550M | — | ❌ |
| VAT Return 2550Q | — | ❌ |
| SLP (Summary List of Purchases) | — | ❌ |
| SLSP Export | — | ❌ |
| RELIEF Export | — | ❌ |
| WT Dashboard | — | ❌ |
| EWT Payable Summary | — | ❌ |
| EWT Receivable Summary | — | ❌ |
| ATC Summary | — | ❌ |
| 1601EQ Working Papers | — | ❌ |
| 1601EQ Quarterly Return | — | ❌ |
| QAP (Quarterly Alphalist of Payees) | — | ❌ |
| SAWT (Summary Alphalist of Withholding Tax) | — | ❌ |
| 2306 Certificates | — | ❌ |
| FWT Working Papers | — | ❌ |
| 1601FQ Working Papers | — | ❌ |
| 1601FQ Quarterly Return | — | ❌ |
| Income Tax Dashboard | — | ❌ |
| Taxable Income Computation | — | ❌ |
| Book-to-Tax Reconciliation | — | ❌ |
| OSD Computation | — | ❌ |
| NOLCO Schedule | — | ❌ |
| Tax Credits Schedule | — | ❌ |
| 1701Q Quarterly ITR | — | ❌ |
| 1701 Annual ITR | — | ❌ |
| 1702Q Quarterly ITR | — | ❌ |
| 1702RT Annual ITR | — | ❌ |
| MCIT Computation | — | ❌ |

---

## BIR Books
| Page | File | Status |
|---|---|---|
| Books Dashboard | — | ❌ |
| General Journal Book | — | ❌ |
| General Ledger Book | — | ❌ |
| Cash Receipts Book | — | ❌ |
| Cash Disbursements Book | — | ❌ |
| Sales Journal | — | ❌ |
| Cash Sales Journal | — | ❌ |
| Purchase Journal | — | ❌ |
| Cash Purchases Journal | — | ❌ |
| AR Subsidiary Ledger Book | — | ❌ |
| AP Subsidiary Ledger Book | — | ❌ |
| Inventory Subsidiary Ledger Book | — | ❌ |
| Fixed Asset Register Book | — | ❌ |

---

## Audit & CAS
| Page | File | Status |
|---|---|---|
| CAS Dashboard | — | ❌ |
| Transaction Audit Log | — | ❌ |
| Master Data Change Log | — | ❌ |
| System Parameter Logs | — | ❌ |
| User Activity Log | — | ❌ |
| Attachment Register | — | ❌ |
| Document Void Register | — | ❌ |
| ATP Usage Log | — | ❌ |
| DAT File Generation | — | ❌ |
| CAS Audit Report | — | ❌ |
| Export History | — | ❌ |

---

## Reports
| Page | File | Status |
|---|---|---|
| Balance Sheet | — | ❌ |
| Income Statement | — | ❌ |
| Statement of Cash Flows | — | ❌ |
| Statement of Changes in Equity | — | ❌ |
| Comparative Financial Statements | — | ❌ |
| Unadjusted Trial Balance | — | ❌ |
| Adjusted Trial Balance | — | ❌ |
| Post-Closing Trial Balance | — | ❌ |
| Output VAT Summary Report | — | ❌ |
| Input VAT Summary Report | — | ❌ |
| Percentage Tax Summary Report | — | ❌ |
| EWT Summary Report | — | ❌ |
| FWT Summary Report | — | ❌ |
| 2307 Issued Listing | — | ❌ |
| 2307 Received Listing | — | ❌ |
| AR Aging Report | — | ❌ |
| AP Aging Report | — | ❌ |
| Bank Position Report | — | ❌ |
| Bank Reconciliation Summary | — | ❌ |
| Outstanding Checks Report | — | ❌ |
| Inventory Valuation Report | — | ❌ |
| Stock Movement Report | — | ❌ |
| Inventory Ledger Report | — | ❌ |
| Slow Moving Inventory Report | — | ❌ |
| Fixed Asset Register Report | — | ❌ |
| Depreciation Schedule Report | — | ❌ |
| Book vs Tax Depreciation Report | — | ❌ |
| Asset Disposal Report | — | ❌ |
| Branch P&L | — | ❌ |
| Department Report | — | ❌ |
| Cost Center Report | — | ❌ |
| Gross Margin Analysis | — | ❌ |
| Journal Register | — | ❌ |
| Sales Invoice Register | — | ❌ |
| Receipt Register | — | ❌ |
| Purchase Register | — | ❌ |
| Payment Register | — | ❌ |
| Credit Memo Register | — | ❌ |
| Debit Memo Register | — | ❌ |
| Check Register | — | ❌ |
| Period Close Checklist Report | — | ❌ |
| Audit Support Package | — | ❌ |
| User Activity Report | — | ❌ |

---

## Totals
| Category | Built | Remaining |
|---|---|---|
| Infrastructure | 5 | 0 |
| Setup | 11 | 0 |
| Master Data | 5 | 3 |
| Dashboard | 1 | 0 |
| Sales / AR | 16 | 0 |
| Purchasing / AP | 14 | 0 |
| Inventory | 0 | 7 |
| Banking & Treasury | 10 | 0 |
| Fixed Assets | 0 | 9 |
| Accounting | 15 | 0 |
| Compliance | 3 | 39 |
| BIR Books | 0 | 13 |
| Audit & CAS | 0 | 11 |
| Reports | 0 | 43 |
| **TOTAL** | **80** | **125** |
