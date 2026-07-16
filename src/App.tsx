import { lazy, Suspense, useEffect, useState } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import LoginPage from '@/pages/LoginPage'
import AuthCallbackPage from '@/pages/AuthCallbackPage'
import AppShell from '@/components/AppShell'
import ErrorBoundary from '@/components/ErrorBoundary'
import type { Session } from '@supabase/supabase-js'

const CompanySetupPage        = lazy(() => import('@/pages/CompanySetupPage'))
const BranchSetupPage         = lazy(() => import('@/pages/BranchSetupPage'))
const DepartmentSetupPage     = lazy(() => import('@/pages/DepartmentSetupPage'))
const FiscalYearsPage         = lazy(() => import('@/pages/FiscalYearsPage'))
const ChartOfAccountsPage     = lazy(() => import('@/pages/ChartOfAccountsPage'))
const CurrencySetupPage       = lazy(() => import('@/pages/CurrencySetupPage'))
const FeatureEnablementPage   = lazy(() => import('@/pages/FeatureEnablementPage'))
const NumberSeriesPage        = lazy(() => import('@/pages/NumberSeriesPage'))
const ApprovalWorkflowPage    = lazy(() => import('@/pages/ApprovalWorkflowPage'))
const AuditLogPage            = lazy(() => import('@/pages/AuditLogPage'))
const CustomersPage           = lazy(() => import('@/pages/CustomersPage'))
const SuppliersPage           = lazy(() => import('@/pages/SuppliersPage'))
const PaymentTermsPage        = lazy(() => import('@/pages/PaymentTermsPage'))
const ItemCatalogPage         = lazy(() => import('@/pages/ItemCatalogPage'))
const TaxSetupPage            = lazy(() => import('@/pages/TaxSetupPage'))
const ComplianceProfilePage   = lazy(() => import('@/pages/ComplianceProfilePage'))
const TaxCalendarPage         = lazy(() => import('@/pages/TaxCalendarPage'))
const BIRFormConfigPage       = lazy(() => import('@/pages/BIRFormConfigPage'))
const DashboardPage           = lazy(() => import('@/pages/DashboardPage'))
const SalesInvoicePage        = lazy(() => import('@/pages/SalesInvoicePage'))
const SalesInvoiceDocumentPage = lazy(() => import('@/pages/SalesInvoiceDocumentPage'))
const ReceiptsPage            = lazy(() => import('@/pages/ReceiptsPage'))
const CreditMemosPage         = lazy(() => import('@/pages/CreditMemosPage'))
const DebitMemosPage          = lazy(() => import('@/pages/DebitMemosPage'))
const QuotationsPage          = lazy(() => import('@/pages/QuotationsPage'))
const SalesOrdersPage         = lazy(() => import('@/pages/SalesOrdersPage'))
const DeliveryReceiptsPage    = lazy(() => import('@/pages/DeliveryReceiptsPage'))
const ARAgingPage             = lazy(() => import('@/pages/ARAgingPage'))
const SalesTaxReviewPage      = lazy(() => import('@/pages/SalesTaxReviewPage'))
const SalesRegistersPage      = lazy(() => import('@/pages/SalesRegistersPage'))
const EWTWorkingPapersPage    = lazy(() => import('@/pages/EWTWorkingPapersPage'))
const Form2307ReceivedPage    = lazy(() => import('@/pages/Form2307ReceivedPage'))
const GLPostingConfigPage     = lazy(() => import('@/pages/GLPostingConfigPage'))
const CashSalesPage           = lazy(() => import('@/pages/CashSalesPage'))
const CollectionMonitoringPage = lazy(() => import('@/pages/CollectionMonitoringPage'))
const PercentageTaxReviewPage = lazy(() => import('@/pages/PercentageTaxReviewPage'))
const SLSPage                 = lazy(() => import('@/pages/SLSPage'))
const CustomerReturnsPage     = lazy(() => import('@/pages/CustomerReturnsPage'))
const VendorBillsPage         = lazy(() => import('@/pages/VendorBillsPage'))
const PaymentVouchersPage     = lazy(() => import('@/pages/PaymentVouchersPage'))
const PurchaseOrdersPage      = lazy(() => import('@/pages/PurchaseOrdersPage'))
const ReceivingReportsPage    = lazy(() => import('@/pages/ReceivingReportsPage'))
const CashPurchasesPage       = lazy(() => import('@/pages/CashPurchasesPage'))
const VendorCreditsPage       = lazy(() => import('@/pages/VendorCreditsPage'))
const SupplierDebitMemosPage  = lazy(() => import('@/pages/SupplierDebitMemosPage'))
const PurchaseReturnsPage     = lazy(() => import('@/pages/PurchaseReturnsPage'))
const APAgingPage             = lazy(() => import('@/pages/APAgingPage'))
const PaymentMonitoringPage   = lazy(() => import('@/pages/PaymentMonitoringPage'))
const InputVATReviewPage      = lazy(() => import('@/pages/InputVATReviewPage'))
const EWTSummaryPage          = lazy(() => import('@/pages/EWTSummaryPage'))
const Form2307IssuedPage      = lazy(() => import('@/pages/Form2307IssuedPage'))
const PurchaseRegistersPage   = lazy(() => import('@/pages/PurchaseRegistersPage'))
const BankAccountsPage        = lazy(() => import('@/pages/BankAccountsPage'))
const PettyCashFundSetupPage  = lazy(() => import('@/pages/PettyCashFundSetupPage'))
const PettyCashVouchersPage   = lazy(() => import('@/pages/PettyCashVouchersPage'))
const PettyCashReplenishmentPage = lazy(() => import('@/pages/PettyCashReplenishmentPage'))
const CashCountSheetPage      = lazy(() => import('@/pages/CashCountSheetPage'))
const FundTransfersPage       = lazy(() => import('@/pages/FundTransfersPage'))
const InterBranchTransfersPage = lazy(() => import('@/pages/InterBranchTransfersPage'))
const BankAdjustmentsPage     = lazy(() => import('@/pages/BankAdjustmentsPage'))
const CheckVouchersPage       = lazy(() => import('@/pages/CheckVouchersPage'))
const BankReconciliationPage  = lazy(() => import('@/pages/BankReconciliationPage'))
const OutstandingChecksPage   = lazy(() => import('@/pages/OutstandingChecksPage'))
const DepositsInTransitPage   = lazy(() => import('@/pages/DepositsInTransitPage'))
const JournalEntriesPage                = lazy(() => import('@/pages/JournalEntriesPage'))
const AccountingTracePage               = lazy(() => import('@/pages/AccountingTracePage'))
const AccountingSourcePage              = lazy(() => import('@/pages/AccountingSourcePage'))
const RecurringJournalTemplatesPage     = lazy(() => import('@/pages/RecurringJournalTemplatesPage'))
const GeneralLedgerPage                 = lazy(() => import('@/pages/GeneralLedgerPage'))
const AccountDetailLedgerPage           = lazy(() => import('@/pages/AccountDetailLedgerPage'))
const TrialBalancePage                  = lazy(() => import('@/pages/TrialBalancePage'))
const PeriodClosingPage                 = lazy(() => import('@/pages/PeriodClosingPage'))
const PostingReviewPage                 = lazy(() => import('@/pages/PostingReviewPage'))
const ReversalReviewPage                = lazy(() => import('@/pages/ReversalReviewPage'))
const ControlAccountReconciliationPage  = lazy(() => import('@/pages/ControlAccountReconciliationPage'))
const AmortizationSchedulesPage         = lazy(() => import('@/pages/AmortizationSchedulesPage'))
const RevenueRecognitionSchedulesPage   = lazy(() => import('@/pages/RevenueRecognitionSchedulesPage'))
const AmortizationRunPage               = lazy(() => import('@/pages/AmortizationRunPage'))
const RevenueRecognitionRunPage         = lazy(() => import('@/pages/RevenueRecognitionRunPage'))
const AutoReversalRunPage               = lazy(() => import('@/pages/AutoReversalRunPage'))
const AssetCategoriesPage               = lazy(() => import('@/pages/AssetCategoriesPage'))
const FixedAssetDashboardPage           = lazy(() => import('@/pages/FixedAssetDashboardPage'))
const AssetRegisterPage                 = lazy(() => import('@/pages/AssetRegisterPage'))
const AssetAcquisitionPage              = lazy(() => import('@/pages/AssetAcquisitionPage'))
const DepreciationRunPage               = lazy(() => import('@/pages/DepreciationRunPage'))
const AssetDisposalPage                 = lazy(() => import('@/pages/AssetDisposalPage'))
const AssetTransferPage                 = lazy(() => import('@/pages/AssetTransferPage'))
const AssetImpairmentPage               = lazy(() => import('@/pages/AssetImpairmentPage'))
const WarehousesPage                    = lazy(() => import('@/pages/WarehousesPage'))
const InventoryDashboardPage            = lazy(() => import('@/pages/InventoryDashboardPage'))
const StockBalancePage                  = lazy(() => import('@/pages/StockBalancePage'))
const StockAdjustmentPage               = lazy(() => import('@/pages/StockAdjustmentPage'))
const StockTransferPage                 = lazy(() => import('@/pages/StockTransferPage'))
const GoodsIssuePage                    = lazy(() => import('@/pages/GoodsIssuePage'))
const PhysicalCountPage                 = lazy(() => import('@/pages/PhysicalCountPage'))
const InventoryMovementsPage            = lazy(() => import('@/pages/InventoryMovementsPage'))
const InventoryValuationPage            = lazy(() => import('@/pages/InventoryValuationPage'))
const WarehouseStockSettingsPage        = lazy(() => import('@/pages/WarehouseStockSettingsPage'))
const EmployeesPage                     = lazy(() => import('@/pages/EmployeesPage'))
const PTDashboardPage                   = lazy(() => import('@/pages/PTDashboardPage'))
const PTWorkingPapersPage               = lazy(() => import('@/pages/PTWorkingPapersPage'))
const PTReturnPage                      = lazy(() => import('@/pages/PTReturnPage'))
const PTReconciliationPage              = lazy(() => import('@/pages/PTReconciliationPage'))
const PTSummaryRegisterPage             = lazy(() => import('@/pages/PTSummaryRegisterPage'))
const VATDashboardPage                  = lazy(() => import('@/pages/VATDashboardPage'))
const VATWorkingPapersPage              = lazy(() => import('@/pages/VATWorkingPapersPage'))
const VATOutputSummaryPage              = lazy(() => import('@/pages/VATOutputSummaryPage'))
const VATInputSummaryPage               = lazy(() => import('@/pages/VATInputSummaryPage'))
const VATReconciliationPage             = lazy(() => import('@/pages/VATReconciliationPage'))
const VATReturn2550MPage                = lazy(() => import('@/pages/VATReturn2550MPage'))
const VATReturn2550QPage                = lazy(() => import('@/pages/VATReturn2550QPage'))
const SLPPage                           = lazy(() => import('@/pages/SLPPage'))
const SLSPExportPage                    = lazy(() => import('@/pages/SLSPExportPage'))
const RELIEFExportPage                  = lazy(() => import('@/pages/RELIEFExportPage'))
const WTDashboardPage                   = lazy(() => import('@/pages/WTDashboardPage'))
const EWTReceivableSummaryPage          = lazy(() => import('@/pages/EWTReceivableSummaryPage'))
const ATCSummaryPage                    = lazy(() => import('@/pages/ATCSummaryPage'))
const EWT1601EQWorkingPapersPage        = lazy(() => import('@/pages/EWT1601EQWorkingPapersPage'))
const EWT1601EQReturnPage               = lazy(() => import('@/pages/EWT1601EQReturnPage'))
const QAPPage                           = lazy(() => import('@/pages/QAPPage'))
const SAWTPage                          = lazy(() => import('@/pages/SAWTPage'))
const Form2306Page                      = lazy(() => import('@/pages/Form2306Page'))
const FWTWorkingPapersPage              = lazy(() => import('@/pages/FWTWorkingPapersPage'))
const FWT1601FQWorkingPapersPage        = lazy(() => import('@/pages/FWT1601FQWorkingPapersPage'))
const FWT1601FQReturnPage               = lazy(() => import('@/pages/FWT1601FQReturnPage'))
const IncomeTaxDashboardPage            = lazy(() => import('@/pages/IncomeTaxDashboardPage'))
const TaxableIncomeComputationPage      = lazy(() => import('@/pages/TaxableIncomeComputationPage'))
const BookToTaxReconciliationPage       = lazy(() => import('@/pages/BookToTaxReconciliationPage'))
const OSDComputationPage                = lazy(() => import('@/pages/OSDComputationPage'))
const NOLCOSchedulePage                 = lazy(() => import('@/pages/NOLCOSchedulePage'))
const TaxCreditsSchedulePage            = lazy(() => import('@/pages/TaxCreditsSchedulePage'))
const ITR1701QPage                      = lazy(() => import('@/pages/ITR1701QPage'))
const ITR1701Page                       = lazy(() => import('@/pages/ITR1701Page'))
const ITR1702QPage                      = lazy(() => import('@/pages/ITR1702QPage'))
const ITR1702RTPage                     = lazy(() => import('@/pages/ITR1702RTPage'))
const MCITComputationPage               = lazy(() => import('@/pages/MCITComputationPage'))
const BooksDashboardPage                = lazy(() => import('@/pages/BooksDashboardPage'))
const BooksGeneralJournalPage           = lazy(() => import('@/pages/BooksGeneralJournalPage'))
const BooksCashReceiptsPage             = lazy(() => import('@/pages/BooksCashReceiptsPage'))
const BooksCashDisbursementsPage        = lazy(() => import('@/pages/BooksCashDisbursementsPage'))
const BooksSalesJournalPage             = lazy(() => import('@/pages/BooksSalesJournalPage'))
const BooksCashSalesJournalPage         = lazy(() => import('@/pages/BooksCashSalesJournalPage'))
const BooksPurchaseJournalPage          = lazy(() => import('@/pages/BooksPurchaseJournalPage'))
const BooksCashPurchasesJournalPage     = lazy(() => import('@/pages/BooksCashPurchasesJournalPage'))
const CASDashboardPage                  = lazy(() => import('@/pages/CASDashboardPage'))
const CASTransactionAuditLogPage        = lazy(() => import('@/pages/CASTransactionAuditLogPage'))
const CASMasterDataChangeLogPage        = lazy(() => import('@/pages/CASMasterDataChangeLogPage'))
const CASSystemParameterLogsPage        = lazy(() => import('@/pages/CASSystemParameterLogsPage'))
const CASUserActivityLogPage            = lazy(() => import('@/pages/CASUserActivityLogPage'))
const CASAttachmentRegisterPage         = lazy(() => import('@/pages/CASAttachmentRegisterPage'))
const CASDocumentVoidRegisterPage       = lazy(() => import('@/pages/CASDocumentVoidRegisterPage'))
const CASATPUsageLogPage                = lazy(() => import('@/pages/CASATPUsageLogPage'))
const CASDATFileGenerationPage          = lazy(() => import('@/pages/CASDATFileGenerationPage'))
const CASAuditReportPage                = lazy(() => import('@/pages/CASAuditReportPage'))
const CASExportHistoryPage              = lazy(() => import('@/pages/CASExportHistoryPage'))
const ReportSnapshotsPage               = lazy(() => import('@/pages/ReportSnapshotsPage'))
const BalanceSheetPage                  = lazy(() => import('@/pages/BalanceSheetPage'))
const IncomeStatementPage               = lazy(() => import('@/pages/IncomeStatementPage'))
const StatementOfCashFlowsPage          = lazy(() => import('@/pages/StatementOfCashFlowsPage'))
const StatementOfChangesInEquityPage    = lazy(() => import('@/pages/StatementOfChangesInEquityPage'))
const ComparativeFinancialStatementsPage = lazy(() => import('@/pages/ComparativeFinancialStatementsPage'))
const FWTSummaryReportPage              = lazy(() => import('@/pages/FWTSummaryReportPage'))
const BankPositionReportPage            = lazy(() => import('@/pages/BankPositionReportPage'))
const SlowMovingInventoryReportPage     = lazy(() => import('@/pages/SlowMovingInventoryReportPage'))
const DepreciationScheduleReportPage    = lazy(() => import('@/pages/DepreciationScheduleReportPage'))
const BookVsTaxDepreciationReportPage   = lazy(() => import('@/pages/BookVsTaxDepreciationReportPage'))
const AssetDisposalReportPage           = lazy(() => import('@/pages/AssetDisposalReportPage'))
const BranchPnLReportPage               = lazy(() => import('@/pages/BranchPnLReportPage'))
const DepartmentReportPage              = lazy(() => import('@/pages/DepartmentReportPage'))
const CostCenterReportPage              = lazy(() => import('@/pages/CostCenterReportPage'))
const GrossMarginAnalysisPage           = lazy(() => import('@/pages/GrossMarginAnalysisPage'))
const CheckRegisterReportPage           = lazy(() => import('@/pages/CheckRegisterReportPage'))
const AuditSupportPackagePage           = lazy(() => import('@/pages/AuditSupportPackagePage'))

const PageLoader = () => (
  <div className="flex items-center justify-center h-64">
    <p className="text-sm text-gray-400">Loading...</p>
  </div>
)

const WelcomeScreen = () => (
  <div className="bg-white rounded-lg border border-gray-200 p-16 text-center">
    <h1 className="text-xl font-semibold text-gray-900">Welcome to PXL</h1>
    <p className="text-sm text-gray-500 mt-1">Philippine Accounting ERP</p>
    <p className="text-xs text-gray-400 mt-3">Select a module from the navigation above</p>
  </div>
)

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setLoading(false)
    })
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
    })
    return () => subscription.unsubscribe()
  }, [])

  if (loading) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <p className="text-sm text-gray-500">Loading...</p>
    </div>
  )

  if (!session) return (
    <ErrorBoundary>
      <Routes>
        <Route path="/auth/callback" element={<AuthCallbackPage />} />
        <Route path="*" element={<LoginPage />} />
      </Routes>
    </ErrorBoundary>
  )

  return (
    <ErrorBoundary>
      <AppShell session={session}>
        <Suspense fallback={<PageLoader />}>
          <Routes>
            <Route path="/" element={<WelcomeScreen />} />
            <Route path="/dashboard" element={<DashboardPage />} />
            <Route path="/company-setup" element={<CompanySetupPage />} />
            <Route path="/branch-setup" element={<BranchSetupPage />} />
            <Route path="/department-setup" element={<DepartmentSetupPage />} />
            <Route path="/fiscal-years" element={<FiscalYearsPage />} />
            <Route path="/chart-of-accounts" element={<ChartOfAccountsPage />} />
            <Route path="/currency-setup" element={<CurrencySetupPage />} />
            <Route path="/feature-enablement" element={<FeatureEnablementPage />} />
            <Route path="/number-series" element={<NumberSeriesPage />} />
            <Route path="/approval-workflow" element={<ApprovalWorkflowPage />} />
            <Route path="/audit-log" element={<AuditLogPage />} />
            <Route path="/customers" element={<CustomersPage />} />
            <Route path="/suppliers" element={<SuppliersPage />} />
            <Route path="/payment-terms" element={<PaymentTermsPage />} />
            <Route path="/item-catalog" element={<ItemCatalogPage />} />
            <Route path="/tax-setup" element={<TaxSetupPage />} />
            <Route path="/compliance-profile" element={<ComplianceProfilePage />} />
            <Route path="/tax-calendar" element={<TaxCalendarPage />} />
            <Route path="/bir-form-config" element={<BIRFormConfigPage />} />
            <Route path="/sales-invoices" element={<SalesInvoicePage />} />
            <Route path="/sales-invoices/new" element={<SalesInvoicePage />} />
            <Route path="/sales-invoices/:id/edit" element={<SalesInvoicePage />} />
            <Route path="/sales-invoices/:id" element={<SalesInvoiceDocumentPage />} />
            <Route path="/receipts" element={<ReceiptsPage />} />
            <Route path="/credit-memos" element={<CreditMemosPage />} />
            <Route path="/debit-memos" element={<DebitMemosPage />} />
            <Route path="/quotations" element={<QuotationsPage />} />
            <Route path="/sales-orders" element={<SalesOrdersPage />} />
            <Route path="/delivery-receipts" element={<DeliveryReceiptsPage />} />
            <Route path="/ar-aging" element={<ARAgingPage />} />
            <Route path="/sales-tax-review" element={<SalesTaxReviewPage />} />
            <Route path="/sales-registers" element={<SalesRegistersPage />} />
            <Route path="/ewt-working-papers" element={<EWTWorkingPapersPage />} />
            <Route path="/2307-received-review" element={<Form2307ReceivedPage />} />
            <Route path="/gl-posting-config" element={<GLPostingConfigPage />} />
            <Route path="/cash-sales" element={<CashSalesPage />} />
            <Route path="/collection-monitoring" element={<CollectionMonitoringPage />} />
            <Route path="/pt-review" element={<PercentageTaxReviewPage />} />
            <Route path="/sls" element={<SLSPage />} />
            <Route path="/customer-returns" element={<CustomerReturnsPage />} />
            <Route path="/vendor-bills" element={<VendorBillsPage />} />
            <Route path="/payment-vouchers" element={<PaymentVouchersPage />} />
            <Route path="/purchase-orders" element={<PurchaseOrdersPage />} />
            <Route path="/receiving-reports" element={<ReceivingReportsPage />} />
            <Route path="/cash-purchases" element={<CashPurchasesPage />} />
            <Route path="/vendor-credits" element={<VendorCreditsPage />} />
            <Route path="/supplier-debit-memos" element={<SupplierDebitMemosPage />} />
            <Route path="/purchase-returns" element={<PurchaseReturnsPage />} />
            <Route path="/ap-aging" element={<APAgingPage />} />
            <Route path="/payment-monitoring" element={<PaymentMonitoringPage />} />
            <Route path="/input-vat-review" element={<InputVATReviewPage />} />
            <Route path="/ewt-summary" element={<EWTSummaryPage />} />
            <Route path="/2307-issued-review" element={<Form2307IssuedPage />} />
            <Route path="/purchase-registers" element={<PurchaseRegistersPage />} />
            <Route path="/bank-accounts" element={<BankAccountsPage />} />
            <Route path="/petty-cash-funds" element={<PettyCashFundSetupPage />} />
            <Route path="/petty-cash-vouchers" element={<PettyCashVouchersPage />} />
            <Route path="/petty-cash-replenishment" element={<PettyCashReplenishmentPage />} />
            <Route path="/cash-count-sheet" element={<CashCountSheetPage />} />
            <Route path="/fund-transfers" element={<FundTransfersPage />} />
            <Route path="/inter-branch-transfers" element={<InterBranchTransfersPage />} />
            <Route path="/bank-adjustments" element={<BankAdjustmentsPage />} />
            <Route path="/check-vouchers" element={<CheckVouchersPage />} />
            <Route path="/bank-reconciliation" element={<BankReconciliationPage />} />
            <Route path="/outstanding-checks" element={<OutstandingChecksPage />} />
            <Route path="/deposits-in-transit" element={<DepositsInTransitPage />} />
            <Route path="/journal-entries" element={<JournalEntriesPage />} />
            <Route path="/accounting-trace" element={<AccountingTracePage />} />
            <Route path="/accounting-source" element={<AccountingSourcePage />} />
            <Route path="/recurring-journal-templates" element={<RecurringJournalTemplatesPage />} />
            <Route path="/general-ledger" element={<GeneralLedgerPage />} />
            <Route path="/account-detail-ledger" element={<AccountDetailLedgerPage />} />
            <Route path="/trial-balance" element={<TrialBalancePage />} />
            <Route path="/period-closing" element={<PeriodClosingPage />} />
            <Route path="/posting-review" element={<PostingReviewPage />} />
            <Route path="/reversal-review" element={<ReversalReviewPage />} />
            <Route path="/control-account-recon" element={<ControlAccountReconciliationPage />} />
            <Route path="/amortization-schedules" element={<AmortizationSchedulesPage />} />
            <Route path="/revenue-recognition-schedules" element={<RevenueRecognitionSchedulesPage />} />
            <Route path="/amortization-run" element={<AmortizationRunPage />} />
            <Route path="/revenue-recognition-run" element={<RevenueRecognitionRunPage />} />
            <Route path="/auto-reversal-run" element={<AutoReversalRunPage />} />
            <Route path="/asset-categories" element={<AssetCategoriesPage />} />
            <Route path="/fixed-asset-dashboard" element={<FixedAssetDashboardPage />} />
            <Route path="/asset-register" element={<AssetRegisterPage />} />
            <Route path="/asset-acquisition" element={<AssetAcquisitionPage />} />
            <Route path="/depreciation-run" element={<DepreciationRunPage />} />
            <Route path="/asset-disposal" element={<AssetDisposalPage />} />
            <Route path="/asset-transfer" element={<AssetTransferPage />} />
            <Route path="/asset-impairment" element={<AssetImpairmentPage />} />
            <Route path="/warehouses" element={<WarehousesPage />} />
            <Route path="/inventory-dashboard" element={<InventoryDashboardPage />} />
            <Route path="/stock-balance" element={<StockBalancePage />} />
            <Route path="/stock-adjustment" element={<StockAdjustmentPage />} />
            <Route path="/stock-transfer" element={<StockTransferPage />} />
            <Route path="/goods-issue" element={<GoodsIssuePage />} />
            <Route path="/physical-count" element={<PhysicalCountPage />} />
            <Route path="/inventory-movements" element={<InventoryMovementsPage />} />
            <Route path="/inventory-valuation" element={<InventoryValuationPage />} />
            <Route path="/warehouse-stock-settings" element={<WarehouseStockSettingsPage />} />
            <Route path="/employees" element={<EmployeesPage />} />
            <Route path="/pt-dashboard" element={<PTDashboardPage />} />
            <Route path="/pt-working-papers" element={<PTWorkingPapersPage />} />
            <Route path="/pt-return-2551q" element={<PTReturnPage />} />
            <Route path="/pt-reconciliation" element={<PTReconciliationPage />} />
            <Route path="/pt-summary-register" element={<PTSummaryRegisterPage />} />
            <Route path="/vat-dashboard" element={<VATDashboardPage />} />
            <Route path="/vat-working-papers" element={<VATWorkingPapersPage />} />
            <Route path="/vat-output-summary" element={<VATOutputSummaryPage />} />
            <Route path="/vat-input-summary" element={<VATInputSummaryPage />} />
            <Route path="/vat-reconciliation" element={<VATReconciliationPage />} />
            <Route path="/vat-return-2550m" element={<VATReturn2550MPage />} />
            <Route path="/vat-return-2550q" element={<VATReturn2550QPage />} />
            <Route path="/vat-slp" element={<SLPPage />} />
            <Route path="/vat-slsp-export" element={<SLSPExportPage />} />
            <Route path="/vat-relief-export" element={<RELIEFExportPage />} />
            <Route path="/wt-dashboard" element={<WTDashboardPage />} />
            <Route path="/wt-ewt-receivable-summary" element={<EWTReceivableSummaryPage />} />
            <Route path="/wt-atc-summary" element={<ATCSummaryPage />} />
            <Route path="/wt-1601eq-working-papers" element={<EWT1601EQWorkingPapersPage />} />
            <Route path="/wt-1601eq-return" element={<EWT1601EQReturnPage />} />
            <Route path="/wt-qap" element={<QAPPage />} />
            <Route path="/wt-sawt" element={<SAWTPage />} />
            <Route path="/wt-2306-certificates" element={<Form2306Page />} />
            <Route path="/wt-fwt-working-papers" element={<FWTWorkingPapersPage />} />
            <Route path="/wt-1601fq-working-papers" element={<FWT1601FQWorkingPapersPage />} />
            <Route path="/wt-1601fq-return" element={<FWT1601FQReturnPage />} />
            <Route path="/inc-tax-dashboard" element={<IncomeTaxDashboardPage />} />
            <Route path="/inc-tax-computation" element={<TaxableIncomeComputationPage />} />
            <Route path="/inc-tax-book-to-tax-recon" element={<BookToTaxReconciliationPage />} />
            <Route path="/inc-tax-osd" element={<OSDComputationPage />} />
            <Route path="/inc-tax-nolco" element={<NOLCOSchedulePage />} />
            <Route path="/inc-tax-credits" element={<TaxCreditsSchedulePage />} />
            <Route path="/inc-tax-1701q" element={<ITR1701QPage />} />
            <Route path="/inc-tax-1701" element={<ITR1701Page />} />
            <Route path="/inc-tax-1702q" element={<ITR1702QPage />} />
            <Route path="/inc-tax-1702rt" element={<ITR1702RTPage />} />
            <Route path="/inc-tax-mcit" element={<MCITComputationPage />} />
            <Route path="/books-dashboard" element={<BooksDashboardPage />} />
            <Route path="/books-general-journal" element={<BooksGeneralJournalPage />} />
            <Route path="/books-cash-receipts" element={<BooksCashReceiptsPage />} />
            <Route path="/books-cash-disbursements" element={<BooksCashDisbursementsPage />} />
            <Route path="/books-sales-journal" element={<BooksSalesJournalPage />} />
            <Route path="/books-cash-sales-journal" element={<BooksCashSalesJournalPage />} />
            <Route path="/books-purchase-journal" element={<BooksPurchaseJournalPage />} />
            <Route path="/books-cash-purchases-journal" element={<BooksCashPurchasesJournalPage />} />
            <Route path="/cas-dashboard" element={<CASDashboardPage />} />
            <Route path="/cas-transaction-audit-log" element={<CASTransactionAuditLogPage />} />
            <Route path="/cas-master-data-change-log" element={<CASMasterDataChangeLogPage />} />
            <Route path="/cas-system-parameter-logs" element={<CASSystemParameterLogsPage />} />
            <Route path="/cas-user-activity-log" element={<CASUserActivityLogPage />} />
            <Route path="/cas-attachment-register" element={<CASAttachmentRegisterPage />} />
            <Route path="/cas-document-void-register" element={<CASDocumentVoidRegisterPage />} />
            <Route path="/cas-atp-usage-log" element={<CASATPUsageLogPage />} />
            <Route path="/cas-dat-file-generation" element={<CASDATFileGenerationPage />} />
            <Route path="/cas-audit-report" element={<CASAuditReportPage />} />
            <Route path="/cas-export-history" element={<CASExportHistoryPage />} />
            <Route path="/report-snapshots" element={<ReportSnapshotsPage />} />
            <Route path="/balance-sheet" element={<BalanceSheetPage />} />
            <Route path="/income-statement" element={<IncomeStatementPage />} />
            <Route path="/statement-of-cash-flows" element={<StatementOfCashFlowsPage />} />
            <Route path="/statement-of-changes-in-equity" element={<StatementOfChangesInEquityPage />} />
            <Route path="/comparative-financial-statements" element={<ComparativeFinancialStatementsPage />} />
            <Route path="/reports-fwt-summary" element={<FWTSummaryReportPage />} />
            <Route path="/reports-bank-position" element={<BankPositionReportPage />} />
            <Route path="/reports-slow-moving-inventory" element={<SlowMovingInventoryReportPage />} />
            <Route path="/reports-depreciation-schedule" element={<DepreciationScheduleReportPage />} />
            <Route path="/reports-book-vs-tax-depreciation" element={<BookVsTaxDepreciationReportPage />} />
            <Route path="/reports-asset-disposal" element={<AssetDisposalReportPage />} />
            <Route path="/reports-branch-pnl" element={<BranchPnLReportPage />} />
            <Route path="/reports-department" element={<DepartmentReportPage />} />
            <Route path="/reports-cost-center" element={<CostCenterReportPage />} />
            <Route path="/reports-gross-margin" element={<GrossMarginAnalysisPage />} />
            <Route path="/reports-check-register" element={<CheckRegisterReportPage />} />
            <Route path="/reports-audit-support-package" element={<AuditSupportPackagePage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Suspense>
      </AppShell>
    </ErrorBoundary>
  )
}
