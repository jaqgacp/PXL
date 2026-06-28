import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Session } from '@supabase/supabase-js'

const NAV_ITEMS = [
  { label: 'Dashboard', modules: [] },
  { label: 'Setup', modules: ['Company', 'Branches', 'Chart of Accounts', 'Fiscal Years', 'Tax Setup', 'Number Series', 'Approval Workflow', 'Feature Settings'] },
  { label: 'Master Data', modules: ['Customers', 'Suppliers', 'Items & Services', 'Warehouses', 'Payment Terms'] },
  { label: 'Sales', modules: ['Sales Invoices', 'Receipts', 'Credit Memos', 'Sales Orders', 'Quotations', 'Delivery Receipts', 'AR Aging'] },
  { label: 'Purchasing', modules: ['Vendor Bills', 'Purchase Orders', 'Receiving Reports', 'Payment Vouchers', 'AP Aging'] },
  { label: 'Inventory', modules: ['Stock Movement', 'Inventory Valuation', 'Stock Adjustment'] },
  { label: 'Banking', modules: ['Petty Cash', 'Fund Transfers', 'Bank Adjustments', 'Bank Reconciliation', 'Check Vouchers'] },
  { label: 'Fixed Assets', modules: ['Asset Register', 'Asset Acquisition', 'Depreciation Run', 'Asset Disposal'] },
  { label: 'Accounting', modules: ['Journal Entries', 'General Ledger', 'Trial Balance', 'Amortization Schedules', 'Period Management'] },
  { label: 'Compliance', modules: ['VAT Returns', 'SLSP / RELIEF', 'EWT Returns', '2307 Certificates', '2306 Certificates', 'BIR Books', 'Tax Calendar'] },
  { label: 'Reports', modules: ['Financial Statements', 'Trial Balance', 'Tax Reports', 'Operational Reports'] },
]

export default function AppShell({ session }: { session: Session }) {
  const [activeMenu, setActiveMenu] = useState<string | null>(null)

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Top Nav */}
      <nav className="fixed top-0 left-0 right-0 h-14 bg-white border-b border-gray-200 z-50 flex items-center px-6 gap-6">
        <span className="font-bold text-gray-900 text-sm tracking-tight mr-4">PXL</span>

        <div className="flex items-center gap-1 flex-1">
          {NAV_ITEMS.map((item) => (
            <div key={item.label} className="relative"
              onMouseEnter={() => setActiveMenu(item.label)}
              onMouseLeave={() => setActiveMenu(null)}>
              <button className={`px-3 py-1.5 text-sm rounded-md transition-colors ${activeMenu === item.label ? 'bg-gray-100 text-gray-900' : 'text-gray-600 hover:text-gray-900 hover:bg-gray-50'}`}>
                {item.label}
              </button>

              {activeMenu === item.label && item.modules.length > 0 && (
                <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg p-3 min-w-48 z-50">
                  {item.modules.map((mod) => (
                    <button key={mod}
                      className="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 rounded-md block">
                      {mod}
                    </button>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>

        <div className="flex items-center gap-3">
          <span className="text-xs text-gray-500">{session.user.email}</span>
          <button onClick={() => supabase.auth.signOut()}
            className="text-xs text-gray-500 hover:text-gray-900 border border-gray-200 rounded px-2 py-1">
            Sign out
          </button>
        </div>
      </nav>

      {/* Main Content */}
      <main className="pt-14 p-6">
        <div className="max-w-7xl mx-auto">
          <div className="bg-white rounded-lg border border-gray-200 p-12 text-center">
            <h1 className="text-2xl font-bold text-gray-900">Welcome to PXL</h1>
            <p className="text-gray-500 mt-2">Philippine Accounting ERP</p>
            <p className="text-sm text-gray-400 mt-4">Dashboard coming in S4.1</p>
          </div>
        </div>
      </main>
    </div>
  )
}