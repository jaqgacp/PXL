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
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Suspense>
      </AppShell>
    </ErrorBoundary>
  )
}
