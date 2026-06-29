import { useEffect, useState } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import LoginPage from '@/pages/LoginPage'
import AuthCallbackPage from '@/pages/AuthCallbackPage'
import AppShell from '@/components/AppShell'
import ErrorBoundary from '@/components/ErrorBoundary'
import type { Session } from '@supabase/supabase-js'

import CompanySetupPage from '@/pages/CompanySetupPage'
import BranchSetupPage from '@/pages/BranchSetupPage'
import DepartmentSetupPage from '@/pages/DepartmentSetupPage'
import FiscalYearsPage from '@/pages/FiscalYearsPage'
import ChartOfAccountsPage from '@/pages/ChartOfAccountsPage'
import CurrencySetupPage from '@/pages/CurrencySetupPage'
import FeatureEnablementPage from '@/pages/FeatureEnablementPage'
import NumberSeriesPage from '@/pages/NumberSeriesPage'
import ApprovalWorkflowPage from '@/pages/ApprovalWorkflowPage'
import AuditLogPage from '@/pages/AuditLogPage'
import CustomersPage from '@/pages/CustomersPage'
import SuppliersPage from '@/pages/SuppliersPage'
import PaymentTermsPage from '@/pages/PaymentTermsPage'
import ItemCatalogPage from '@/pages/ItemCatalogPage'
import TaxSetupPage from '@/pages/TaxSetupPage'
import ComplianceProfilePage from '@/pages/ComplianceProfilePage'
import TaxCalendarPage from '@/pages/TaxCalendarPage'
import BIRFormConfigPage from '@/pages/BIRFormConfigPage'
import DashboardPage from '@/pages/DashboardPage'
import SalesInvoicePage from '@/pages/SalesInvoicePage'
import ReceiptsPage from '@/pages/ReceiptsPage'
import CreditMemosPage from '@/pages/CreditMemosPage'
import DebitMemosPage from '@/pages/DebitMemosPage'
import QuotationsPage from '@/pages/QuotationsPage'
import SalesOrdersPage from '@/pages/SalesOrdersPage'
import DeliveryReceiptsPage from '@/pages/DeliveryReceiptsPage'
import ARAgingPage from '@/pages/ARAgingPage'
import SalesTaxReviewPage from '@/pages/SalesTaxReviewPage'
import SalesRegistersPage from '@/pages/SalesRegistersPage'
import EWTWorkingPapersPage from '@/pages/EWTWorkingPapersPage'
import Form2307ReceivedPage from '@/pages/Form2307ReceivedPage'

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
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
    </ErrorBoundary>
  )
}
