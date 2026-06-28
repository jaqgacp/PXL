import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import CompanySetupPage from '@/pages/CompanySetupPage'
import type { Session } from '@supabase/supabase-js'

type SubItem = { name: string; page: string }
type Group = { group: string; items: SubItem[] }
type NavItem = { label: string; groups: Group[] }

const s = (name: string, page = ''): SubItem => ({ name, page })

const NAV: NavItem[] = [
  { label: 'Dashboard', groups: [] },
  {
    label: 'Setup', groups: [
      { group: 'Organization', items: [
        s('Company Setup', 'company-setup'),
        s('Branch Setup'), s('Department Setup'), s('Cost Centers'),
        s('CAS Registrations'), s('Company Bank Accounts'), s('Compliance Profile'),
      ]},
      { group: 'System Controls', items: [
        s('Number Series — Sales'), s('Number Series — Purchasing'),
        s('Number Series — Accounting'), s('Number Series — Compliance'),
        s('ATP Monitoring'), s('Global Feature Enablement'),
        s('Inventory Settings'), s('Fixed Assets Settings'),
        s('Petty Cash Settings'), s('Bank Reconciliation Settings'),
        s('Budget Settings'), s('Unified Approval Workflow'),
      ]},
      { group: 'Document & Validation', items: [
        s('Status Controls'), s('Posting Controls'),
        s('Void Controls'), s('Reversal Controls'),
        s('Master Data Rules'), s('Transaction Rules'),
        s('Posting Validation Rules'), s('Period Controls'),
      ]},
      { group: 'Accounting Setup', items: [
        s('Fiscal Years'), s('Fiscal Calendar'), s('Chart of Accounts'),
        s('Currency Setup'), s('Exchange Rates'), s('Opening Balances'),
        s('Financial Statement Fields'), s('GL Posting Configuration'),
      ]},
      { group: 'Tax Setup', items: [
        s('BIR Form Configuration'), s('Tax Codes'), s('VAT Codes'),
        s('EWT Codes'), s('FWT Codes'), s('Percentage Tax Codes'),
        s('ATC Codes'), s('Tax Calendar'),
      ]},
      { group: 'System', items: [s('System Audit Log')] },
    ]
  },
  {
    label: 'Master Data', groups: [
      { group: 'Parties', items: [s('Customers'), s('Suppliers'), s('Personnel / Employees Lite')] },
      { group: 'Items & Services', items: [s('Item Categories'), s('Units of Measure'), s('Items'), s('Services')] },
      { group: 'Inventory Master', items: [s('Warehouses'), s('Warehouse Stock Settings')] },
      { group: 'Shared', items: [s('Payment Terms')] },
    ]
  },
  {
    label: 'Sales', groups: [
      { group: 'Transactions', items: [
        s('Quotations'), s('Sales Orders'), s('Delivery Receipts'),
        s('Sales Invoices'), s('Cash Sales'), s('Receipts'),
        s('Credit Memos'), s('Debit Memos'), s('Customer Returns'),
      ]},
      { group: 'Receivables', items: [s('Customer Ledger'), s('AR Aging'), s('Collection Monitoring')] },
      { group: 'Tax Review', items: [s('Output VAT Review'), s('Percentage Tax Review'), s('2307 Received Review')] },
      { group: 'Registers', items: [s('Sales Invoice Register'), s('Receipt Register'), s('Credit Memo Register'), s('Debit Memo Register'), s('SLS')] },
    ]
  },
  {
    label: 'Purchasing', groups: [
      { group: 'Transactions', items: [
        s('Purchase Orders'), s('Receiving Reports'), s('Vendor Bills'),
        s('Cash Purchases'), s('Payment Vouchers'), s('Vendor Credits'),
        s('Debit Memos to Suppliers'), s('Purchase Returns'),
      ]},
      { group: 'Payables', items: [s('Supplier Ledger'), s('AP Aging'), s('Payment Monitoring')] },
      { group: 'Tax Review', items: [s('Input VAT Review'), s('EWT Summary'), s('2307 Issued Review')] },
      { group: 'Registers', items: [s('Vendor Bill Register'), s('Payment Register'), s('Debit Memo Register'), s('SLP')] },
    ]
  },
  {
    label: 'Inventory', groups: [
      { group: 'Operations', items: [
        s('Inventory Dashboard'), s('Stock Adjustment'), s('Stock Transfer'),
        s('Goods Issue'), s('Physical Count'), s('Inventory Movements'), s('Inventory Valuation'),
      ]},
      { group: 'Master Data', items: [s('Items'), s('Warehouses')] },
    ]
  },
  {
    label: 'Banking & Treasury', groups: [
      { group: 'Petty Cash', items: [s('Petty Cash Fund Setup'), s('Petty Cash Vouchers'), s('Petty Cash Replenishment'), s('Cash Count Sheet')] },
      { group: 'Bank Operations', items: [s('Fund Transfers'), s('Inter-Branch Transfers'), s('Bank Adjustments'), s('Bank Reconciliation'), s('Outstanding Checks'), s('Deposits in Transit')] },
      { group: 'Payables', items: [s('Check Vouchers')] },
    ]
  },
  {
    label: 'Fixed Assets', groups: [
      { group: 'Operations', items: [s('Fixed Asset Dashboard'), s('Asset Register'), s('Asset Acquisition'), s('Depreciation'), s('Disposal'), s('Transfer'), s('Impairment')] },
      { group: 'Setup', items: [s('Asset Categories'), s('Depreciation Profiles')] },
    ]
  },
  {
    label: 'Accounting', groups: [
      { group: 'Journal Entries', items: [s('General Ledger Entries'), s('Journal Entries'), s('Recurring Journal Templates')] },
      { group: 'Ledgers', items: [s('General Ledger'), s('Account Detail Ledger'), s('Trial Balance')] },
      { group: 'Subsidiary Ledgers', items: [s('Customer Ledger (Accounting View)'), s('Supplier Ledger (Accounting View)'), s('Control Account Reconciliation')] },
      { group: 'Schedules', items: [s('Amortization Schedules'), s('Revenue Recognition Schedules')] },
      { group: 'Period Management', items: [s('Period Closing'), s('Fiscal Locks'), s('Posting Review'), s('Reversal Review'), s('Amortization Run'), s('Revenue Recognition Run'), s('Auto Reversal Run')] },
    ]
  },
  {
    label: 'Compliance', groups: [
      { group: 'Percentage Tax', items: [s('PT Dashboard'), s('PT Working Papers'), s('PT Quarterly Return 2551Q'), s('PT Reconciliation'), s('PT Summary Register')] },
      { group: 'VAT', items: [s('VAT Dashboard'), s('VAT Working Papers'), s('Output VAT Summary'), s('Input VAT Summary'), s('VAT Reconciliation'), s('VAT Return 2550M'), s('VAT Return 2550Q'), s('SLS'), s('SLP'), s('SLSP Export'), s('RELIEF Export')] },
      { group: 'Withholding Tax', items: [s('WT Dashboard'), s('EWT Working Papers'), s('EWT Payable Summary'), s('EWT Receivable Summary'), s('ATC Summary'), s('1601EQ Working Papers'), s('1601EQ Quarterly Return'), s('QAP'), s('SAWT'), s('2307 Certificates Issued'), s('2307 Certificates Received'), s('2306 Certificates'), s('FWT Working Papers'), s('1601FQ Working Papers'), s('1601FQ Quarterly Return')] },
      { group: 'Income Tax', items: [s('Income Tax Dashboard'), s('Taxable Income Computation'), s('Book-to-Tax Reconciliation'), s('OSD Computation'), s('NOLCO Schedule'), s('Tax Credits Schedule'), s('1701Q Quarterly ITR'), s('1701 Annual ITR'), s('1702Q Quarterly ITR'), s('1702RT Annual ITR'), s('MCIT Computation')] },
      { group: 'BIR Books', items: [s('Books Dashboard'), s('General Journal'), s('General Ledger Book'), s('Cash Receipts Book'), s('Cash Disbursements Book'), s('Sales Journal'), s('Cash Sales Journal'), s('Purchase Journal'), s('Cash Purchases Journal'), s('AR Subsidiary Ledger'), s('AP Subsidiary Ledger'), s('Inventory Subsidiary Ledger'), s('Fixed Asset Register')] },
      { group: 'Audit & CAS', items: [s('CAS Dashboard'), s('Transaction Audit Log'), s('Master Data Change Log'), s('System Parameter Logs'), s('User Activity Log'), s('Attachment Register'), s('Document Void Register'), s('ATP Usage Log'), s('DAT File Generation'), s('CAS Audit Report'), s('Export History')] },
    ]
  },
  {
    label: 'Reports', groups: [
      { group: 'Financial Statements', items: [s('Balance Sheet'), s('Income Statement'), s('Statement of Cash Flows'), s('Statement of Changes in Equity'), s('Comparative Financial Statements')] },
      { group: 'Trial Balance', items: [s('Unadjusted Trial Balance'), s('Adjusted Trial Balance'), s('Post-Closing Trial Balance')] },
      { group: 'Tax Reports', items: [s('Output VAT Summary'), s('Input VAT Summary'), s('Percentage Tax Summary'), s('EWT Summary'), s('FWT Summary'), s('2307 Issued Listing'), s('2307 Received Listing')] },
      { group: 'Aging Reports', items: [s('AR Aging'), s('AP Aging')] },
      { group: 'Bank Reports', items: [s('Bank Position Report'), s('Bank Reconciliation Summary'), s('Outstanding Checks Report')] },
      { group: 'Inventory Reports', items: [s('Inventory Valuation'), s('Stock Movement'), s('Inventory Ledger'), s('Slow Moving Inventory')] },
      { group: 'Fixed Asset Reports', items: [s('Fixed Asset Register'), s('Depreciation Schedule'), s('Book vs Tax Depreciation'), s('Asset Disposal Report')] },
      { group: 'Management Reports', items: [s('Branch P&L'), s('Department Report'), s('Cost Center Report'), s('Gross Margin Analysis')] },
      { group: 'Transaction Registers', items: [s('Journal Register'), s('Sales Invoice Register'), s('Receipt Register'), s('Purchase Register'), s('Payment Register'), s('Credit Memo Register'), s('Debit Memo Register'), s('Check Register')] },
      { group: 'Audit Reports', items: [s('Period Close Checklist'), s('Audit Support Package'), s('User Activity Report')] },
    ]
  },
]

export default function AppShell({ session }: { session: Session }) {
  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [activeGroup, setActiveGroup] = useState<string | null>(null)
  const [currentPage, setCurrentPage] = useState('')

  const openMenu = (label: string) => {
    setActiveMenu(label)
    const nav = NAV.find(n => n.label === label)
    if (nav && nav.groups.length > 0) setActiveGroup(nav.groups[0].group)
  }

  const closeMenu = () => { setActiveMenu(null); setActiveGroup(null) }

  const navigate = (page: string) => {
    if (!page) return
    setCurrentPage(page)
    closeMenu()
  }

  const currentNav = NAV.find(n => n.label === activeMenu)
  const currentGroupItems = currentNav?.groups.find(g => g.group === activeGroup)?.items ?? []

  const renderPage = () => {
    if (currentPage === 'company-setup') return <CompanySetupPage />
    return (
      <div className="bg-white rounded-lg border border-gray-200 p-16 text-center">
        <h1 className="text-xl font-semibold text-gray-900">Welcome to PXL</h1>
        <p className="text-sm text-gray-500 mt-1">Philippine Accounting ERP</p>
        <p className="text-xs text-gray-400 mt-3">Select a module from the navigation above</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="fixed top-0 left-0 right-0 h-14 bg-gray-900 z-50 flex items-center px-6 border-b border-gray-800">
        <span onClick={() => { setCurrentPage(''); closeMenu() }}
          className="font-bold text-white text-sm tracking-tight mr-6 cursor-pointer shrink-0">
          PXL
        </span>

        <div className="flex items-center h-14 flex-1">
          {NAV.map((item) => (
            <div key={item.label} className="relative h-14 flex items-center"
              onMouseEnter={() => openMenu(item.label)}
              onMouseLeave={closeMenu}>

              <button className={`px-3 h-14 text-sm transition-colors border-b-2 whitespace-nowrap ${
                activeMenu === item.label
                  ? 'text-white border-blue-400 bg-gray-800'
                  : 'text-gray-300 border-transparent hover:text-white hover:bg-gray-800'
              }`}>
                {item.label}
              </button>

              {activeMenu === item.label && currentNav && currentNav.groups.length > 0 && (
                <div className="absolute top-14 left-0 flex shadow-2xl border border-gray-200 rounded-b-lg overflow-hidden z-50">
                  {/* Left panel — group list */}
                  <div className="bg-gray-800 w-52 py-2 shrink-0">
                    <p className="px-4 py-1.5 text-xs font-semibold text-gray-500 uppercase tracking-widest">
                      {item.label}
                    </p>
                    {currentNav.groups.map(g => (
                      <button key={g.group}
                        onMouseEnter={() => setActiveGroup(g.group)}
                        className={`w-full text-left px-4 py-2 text-sm flex items-center justify-between transition-colors ${
                          activeGroup === g.group
                            ? 'bg-gray-700 text-white'
                            : 'text-gray-300 hover:bg-gray-700 hover:text-white'
                        }`}>
                        {g.group}
                        <span className="text-gray-500 text-xs ml-2">›</span>
                      </button>
                    ))}
                  </div>

                  {/* Right panel — items */}
                  <div className="bg-white w-56 py-3 overflow-y-auto max-h-96">
                    <p className="px-4 pb-1.5 text-xs font-semibold text-gray-400 uppercase tracking-widest">
                      {activeGroup}
                    </p>
                    {currentGroupItems.map(mod => (
                      <button key={mod.name}
                        onClick={() => navigate(mod.page)}
                        className={`w-full text-left px-4 py-1.5 text-sm transition-colors ${
                          mod.page
                            ? 'text-gray-700 hover:bg-blue-50 hover:text-blue-700'
                            : 'text-gray-400 cursor-not-allowed'
                        }`}>
                        {mod.name}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>

        <div className="flex items-center gap-3 ml-4">
          <span className="text-xs text-gray-400 truncate max-w-36">{session.user.email}</span>
          <button onClick={() => supabase.auth.signOut()}
            className="text-xs text-gray-400 hover:text-white border border-gray-700 rounded px-2 py-1 transition-colors shrink-0">
            Sign out
          </button>
        </div>
      </nav>

      {activeMenu && <div className="fixed inset-0 z-40" onClick={closeMenu} />}

      <main className="pt-14 p-6">
        <div className="max-w-7xl mx-auto">{renderPage()}</div>
      </main>
    </div>
  )
}