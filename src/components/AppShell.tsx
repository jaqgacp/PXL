import React, { useState, useEffect } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { AppContextProvider, useAppCtx } from '@/lib/context'
import type { Session } from '@supabase/supabase-js'

type SubItem = { name: string; page: string; feature?: string }
type Group = { group: string; items: SubItem[] }
type NavItem = { label: string; groups: Group[]; page?: string; feature?: string }

const s = (name: string, page = ''): SubItem => ({ name, page })

const NAV: NavItem[] = [
  { label: 'Dashboard', groups: [], page: 'dashboard' },
  {
    label: 'Setup', groups: [
      { group: 'Organization', items: [
        s('Company Setup', 'company-setup'),
        s('Branch Setup', 'branch-setup'),
        s('Department Setup', 'department-setup'),
        s('Cost Centers', 'department-setup'),
        s('CAS Registrations'), s('Company Bank Accounts'), s('Compliance Profile', 'compliance-profile'),
      ]},
      { group: 'System Controls', items: [
        s('Number Series — Sales', 'number-series'),
        s('Number Series — Purchasing', 'number-series'),
        s('Number Series — Accounting', 'number-series'),
        s('Number Series — Compliance', 'number-series'),
        s('ATP Monitoring'),
        s('Global Feature Enablement', 'feature-enablement'),
        s('Inventory Settings'), s('Fixed Assets Settings'),
        s('Petty Cash Settings'), s('Bank Reconciliation Settings'),
        s('Budget Settings'),
        s('Unified Approval Workflow', 'approval-workflow'),
      ]},
      { group: 'Document & Validation', items: [
        s('Status Controls'), s('Posting Controls'),
        s('Void Controls'), s('Reversal Controls'),
        s('Master Data Rules'), s('Transaction Rules'),
        s('Posting Validation Rules'), s('Period Controls'),
      ]},
      { group: 'Accounting Setup', items: [
        s('Fiscal Years', 'fiscal-years'),
        s('Fiscal Calendar', 'fiscal-years'),
        s('Chart of Accounts', 'chart-of-accounts'),
        s('Currency Setup', 'currency-setup'),
        s('Exchange Rates', 'currency-setup'),
        s('Opening Balances'),
        s('Financial Statement Fields'), s('GL Posting Configuration', 'gl-posting-config'),
      ]},
      { group: 'Tax Setup', items: [
        s('BIR Form Configuration', 'bir-form-config'),
        s('Tax Codes', 'tax-setup'), s('VAT Codes', 'tax-setup'),
        s('EWT Codes', 'tax-setup'), s('FWT Codes', 'tax-setup'),
        s('Percentage Tax Codes', 'tax-setup'), s('ATC Codes', 'tax-setup'),
        s('Tax Calendar', 'tax-calendar'),
      ]},
      { group: 'Treasury', items: [s('Petty Cash Fund Setup', 'petty-cash-funds')] },
      { group: 'System', items: [s('System Audit Log', 'audit-log')] },
    ]
  },
  {
    label: 'Master Data', groups: [
      { group: 'Parties', items: [s('Customers', 'customers'), s('Suppliers', 'suppliers'), s('Personnel / Employees Lite')] },
      { group: 'Items & Services', items: [s('Item Categories', 'item-catalog'), s('Units of Measure', 'item-catalog'), s('Items', 'item-catalog'), s('Services', 'item-catalog')] },
      { group: 'Inventory Master', items: [s('Warehouses'), s('Warehouse Stock Settings')] },
      { group: 'Shared', items: [s('Payment Terms', 'payment-terms')] },
      { group: 'Banking', items: [s('Bank Accounts', 'bank-accounts')] },
    ]
  },
  {
    label: 'Sales', feature: 'accounts_receivable', groups: [
      { group: 'Transactions', items: [
        s('Quotations', 'quotations'), s('Sales Orders', 'sales-orders'), s('Delivery Receipts', 'delivery-receipts'),
        s('Sales Invoices', 'sales-invoices'), s('Cash Sales', 'cash-sales'),
        s('Receipts', 'receipts'),
        s('Credit Memos', 'credit-memos'), s('Debit Memos', 'debit-memos'), s('Customer Returns', 'customer-returns'),
      ]},
      { group: 'Receivables', items: [s('AR Aging / Customer Ledger', 'ar-aging'), s('Collection Monitoring', 'collection-monitoring')] },
      { group: 'Tax Review', items: [s('Output VAT Review', 'sales-tax-review'), s('Percentage Tax Review', 'pt-review'), s('2307 Received Review', '2307-received-review')] },
      { group: 'Registers', items: [s('Sales Registers', 'sales-registers'), s('SLS', 'sls')] },
    ]
  },
  {
    label: 'Purchasing', feature: 'accounts_payable', groups: [
      { group: 'Transactions', items: [
        s('Purchase Orders', 'purchase-orders'),
        s('Receiving Reports', 'receiving-reports'),
        s('Vendor Bills', 'vendor-bills'),
        s('Cash Purchases', 'cash-purchases'),
        s('Payment Vouchers', 'payment-vouchers'),
        s('Vendor Credits', 'vendor-credits'),
        s('Debit Memos to Suppliers', 'supplier-debit-memos'),
        s('Purchase Returns', 'purchase-returns'),
      ]},
      { group: 'Payables', items: [
        s('AP Aging / Supplier Ledger', 'ap-aging'),
        s('Payment Monitoring', 'payment-monitoring'),
      ]},
      { group: 'Tax Review', items: [
        s('Input VAT Review', 'input-vat-review'),
        s('EWT Summary', 'ewt-summary'),
        s('2307 Issued Review', '2307-issued-review'),
      ]},
      { group: 'Registers', items: [
        s('Purchase Registers', 'purchase-registers'),
      ]},
    ]
  },
  {
    label: 'Inventory', feature: 'inventory_management', groups: [
      { group: 'Operations', items: [
        s('Inventory Dashboard'), s('Stock Adjustment'), s('Stock Transfer'),
        s('Goods Issue'), s('Physical Count'), s('Inventory Movements'), s('Inventory Valuation'),
      ]},
      { group: 'Master Data', items: [s('Items'), s('Warehouses')] },
    ]
  },
  {
    label: 'Banking & Treasury', feature: 'banking_module', groups: [
      { group: 'Petty Cash', items: [
        s('Petty Cash Fund Setup', 'petty-cash-funds'),
        s('Petty Cash Vouchers', 'petty-cash-vouchers'),
        s('Petty Cash Replenishment', 'petty-cash-replenishment'),
        s('Cash Count Sheet', 'cash-count-sheet'),
      ]},
      { group: 'Bank Operations', items: [
        s('Fund Transfers', 'fund-transfers'),
        s('Inter-Branch Transfers', 'inter-branch-transfers'),
        s('Bank Adjustments', 'bank-adjustments'),
        s('Bank Reconciliation', 'bank-reconciliation'),
        s('Outstanding Checks', 'outstanding-checks'),
        s('Deposits in Transit', 'deposits-in-transit'),
      ]},
      { group: 'Payables', items: [
        s('Check Vouchers', 'check-vouchers'),
      ]},
    ]
  },
  {
    label: 'Fixed Assets', feature: 'fixed_assets', groups: [
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
      { group: 'Withholding Tax', items: [s('WT Dashboard'), s('EWT Working Papers', 'ewt-working-papers'), s('EWT Payable Summary'), s('EWT Receivable Summary'), s('ATC Summary'), s('1601EQ Working Papers'), s('1601EQ Quarterly Return'), s('QAP'), s('SAWT'), s('2307 Certificates Issued'), s('2307 Certificates Received'), s('2306 Certificates'), s('FWT Working Papers'), s('1601FQ Working Papers'), s('1601FQ Quarterly Return')] },
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

const PAGE_LABELS: Record<string, string> = {
  'company-setup': 'Company Setup',
  'branch-setup': 'Branch Setup',
  'department-setup': 'Departments & Cost Centers',
  'fiscal-years': 'Fiscal Years',
  'chart-of-accounts': 'Chart of Accounts',
  'currency-setup': 'Currency Setup',
  'feature-enablement': 'Feature Enablement',
  'number-series': 'Number Series',
  'approval-workflow': 'Approval Workflows',
  'audit-log': 'System Audit Log',
  'customers': 'Customers',
  'suppliers': 'Suppliers',
  'payment-terms': 'Payment Terms',
  'item-catalog': 'Item Catalog',
  'tax-setup': 'Tax Code Setup',
  'compliance-profile': 'Compliance Profile',
  'tax-calendar': 'Tax Calendar',
  'bir-form-config': 'BIR Form Configuration',
  'dashboard': 'Executive Dashboard',
  'sales-invoices': 'Sales Invoices',
  'receipts':            'Receipts',
  'credit-memos':        'Credit Memos',
  'debit-memos':         'Debit Memos',
  'quotations':          'Quotations',
  'sales-orders':        'Sales Orders',
  'delivery-receipts':   'Delivery Receipts',
  'ar-aging':            'AR Aging & Customer Ledger',
  'sales-tax-review':    'Output VAT Review',
  'sales-registers':        'Sales Registers',
  'ewt-working-papers':     'EWT Working Papers',
  '2307-received-review':   '2307 Received Review',
  'gl-posting-config':      'GL Posting Configuration',
  'cash-sales':             'Cash Sales',
  'collection-monitoring':  'Collection Monitoring',
  'pt-review':              'Percentage Tax Review',
  'sls':                    'Summary List of Sales (SLS)',
  'customer-returns':       'Customer Returns',
  'vendor-bills':           'Vendor Bills',
  'payment-vouchers':       'Payment Vouchers',
  'purchase-orders':        'Purchase Orders',
  'receiving-reports':      'Receiving Reports',
  'cash-purchases':         'Cash Purchases',
  'vendor-credits':         'Vendor Credits',
  'supplier-debit-memos':   'Debit Memos to Suppliers',
  'purchase-returns':       'Purchase Returns',
  'ap-aging':               'AP Aging & Supplier Ledger',
  'payment-monitoring':     'Payment Monitoring',
  'input-vat-review':       'Input VAT Review',
  'ewt-summary':            'EWT Summary',
  '2307-issued-review':     '2307 Issued Review',
  'purchase-registers':     'Purchase Registers',
  'bank-accounts':          'Bank Accounts',
  'petty-cash-funds':       'Petty Cash Fund Setup',
  'petty-cash-vouchers':    'Petty Cash Vouchers',
  'petty-cash-replenishment': 'Petty Cash Replenishment',
  'cash-count-sheet':       'Cash Count Sheet',
  'fund-transfers':         'Fund Transfers',
  'inter-branch-transfers': 'Inter-Branch Transfers',
  'bank-adjustments':       'Bank Adjustments',
  'check-vouchers':         'Check Vouchers',
  'bank-reconciliation':    'Bank Reconciliation',
  'outstanding-checks':     'Outstanding Checks',
  'deposits-in-transit':    'Deposits in Transit',
}

function findSection(page: string): string | null {
  for (const nav of NAV) {
    for (const group of nav.groups) {
      if (group.items.some(item => item.page === page)) return nav.label
    }
  }
  return null
}

function ContextSelectors() {
  const { companyId, branchId, periodId, setCompanyId, setBranchId, setPeriodId } = useAppCtx()
  const [companies, setCompanies] = useState<Array<{ id: string; registered_name: string }>>([])
  const [branches, setBranches] = useState<Array<{ id: string; branch_code: string; branch_name: string }>>([])
  const [periods, setPeriods] = useState<Array<{ id: string; period_name: string; fiscal_year_id: string }>>([])

  useEffect(() => {
    supabase.from('companies').select('id,registered_name').eq('is_active', true).order('registered_name')
      .then(({ data }) => setCompanies(data || []))
  }, [])

  useEffect(() => {
    if (!companyId) { setBranches([]); setPeriods([]); return }
    supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true).order('branch_name')
      .then(({ data }) => setBranches(data || []))
    supabase.from('fiscal_periods').select('id,period_name,fiscal_year_id').eq('company_id', companyId).eq('is_locked', false).order('start_date', { ascending: false }).limit(24)
      .then(({ data }) => setPeriods(data || []))
  }, [companyId])

  const sel = 'border border-gray-700 bg-gray-800 text-gray-300 text-xs rounded px-2 py-1 focus:outline-none focus:ring-1 focus:ring-blue-400 cursor-pointer max-w-[140px] truncate'

  return (
    <div className="flex items-center gap-1.5 shrink-0">
      <select value={companyId} onChange={e => { setCompanyId(e.target.value); setBranchId(''); setPeriodId('') }} className={sel} title="Company">
        <option value="">Company</option>
        {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
      </select>
      <select value={branchId} onChange={e => setBranchId(e.target.value)} disabled={!companyId} className={`${sel} disabled:opacity-40 disabled:cursor-not-allowed`} title="Branch">
        <option value="">Branch</option>
        {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
      </select>
      <select value={periodId} onChange={e => setPeriodId(e.target.value)} disabled={!companyId} className={`${sel} disabled:opacity-40 disabled:cursor-not-allowed`} title="Period">
        <option value="">Period</option>
        {periods.map(p => <option key={p.id} value={p.id}>{p.period_name}</option>)}
      </select>
    </div>
  )
}

function AppShellInner({ session, children }: { session: Session; children: React.ReactNode }) {
  const rrNavigate = useNavigate()
  const location = useLocation()
  const { companyId } = useAppCtx()
  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [activeGroup, setActiveGroup] = useState<string | null>(null)
  const [menuLeft, setMenuLeft] = useState(0)
  // null = not yet loaded or no company selected → show all nav items
  const [enabledFeatures, setEnabledFeatures] = useState<Set<string> | null>(null)

  useEffect(() => {
    if (!companyId) { setEnabledFeatures(null); return }
    Promise.all([
      supabase.from('ref_feature_definitions').select('feature_key').eq('always_enabled', true),
      supabase.from('sys_feature_enablement').select('feature_key').eq('company_id', companyId).eq('is_enabled', true),
    ]).then(([alwaysRes, companyRes]) => {
      const companyRows = companyRes.data || []
      // If the company has no feature records configured yet, show everything (default-open)
      if (companyRows.length === 0) { setEnabledFeatures(null); return }
      const keys = new Set<string>()
      for (const r of alwaysRes.data || []) keys.add(r.feature_key)
      for (const r of companyRows) keys.add(r.feature_key)
      setEnabledFeatures(keys)
    })
  }, [companyId])

  // Show all nav items when features are not configured; only gate when explicitly loaded
  const visibleNav = enabledFeatures === null
    ? NAV
    : NAV.filter(n => !n.feature || enabledFeatures.has(n.feature))

  const currentPage = location.pathname.slice(1) // e.g. "company-setup"
  const breadcrumbSection = currentPage ? findSection(currentPage) : null

  const openMenu = (label: string, left = 0) => {
    setActiveMenu(label)
    setMenuLeft(left)
    const nav = NAV.find(n => n.label === label)
    if (nav && nav.groups.length > 0) setActiveGroup(nav.groups[0].group)
  }

  const closeMenu = () => { setActiveMenu(null); setActiveGroup(null) }

  const navigate = (page: string) => {
    if (!page) return
    rrNavigate(`/${page}`)
    closeMenu()
  }

  const currentNav = NAV.find(n => n.label === activeMenu)
  const currentGroupItems = currentNav?.groups.find(g => g.group === activeGroup)?.items ?? []

  return (
    <div className="min-h-screen bg-gray-50">
      {/*
        Nav bar: mouseLeave on the <nav> element closes the menu.
        Dropdown is a direct child of <nav> (not inside the scroll container)
        so overflow-x-auto on the scroll container cannot clip it.
      */}
      <nav className="fixed top-0 left-0 right-0 h-14 bg-gray-900 z-50 border-b border-gray-800 relative"
        onMouseLeave={closeMenu}>

        <div className="flex items-center h-14">
          {/* Logo */}
          <span onClick={() => { rrNavigate('/'); closeMenu() }}
            className="font-bold text-white text-sm tracking-tight px-4 cursor-pointer shrink-0">
            PXL
          </span>

          {/* Nav buttons — scrollable, no visible scrollbar. Dropdown is NOT here. */}
          <div className="flex items-center h-14 flex-1 min-w-0 overflow-x-auto"
            style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' } as React.CSSProperties}>
            {visibleNav.map((item) => (
              <button key={item.label}
                onMouseEnter={(e) => openMenu(item.label, (e.currentTarget as HTMLElement).getBoundingClientRect().left)}
                onClick={() => { if (item.page) { navigate(item.page); closeMenu() } }}
                className={`shrink-0 px-3 h-14 text-sm transition-colors border-b-2 whitespace-nowrap ${
                  activeMenu === item.label || (item.page !== undefined && location.pathname === `/${item.page}`)
                    ? 'text-white border-blue-400 bg-gray-800'
                    : 'text-gray-300 border-transparent hover:text-white hover:bg-gray-800'
                }`}>
                {item.label}
              </button>
            ))}
          </div>

          {/* Context selectors + user — right side */}
          <div className="flex items-center gap-2 shrink-0 px-3 border-l border-gray-800 ml-1">
            <ContextSelectors />
            <div className="w-px h-5 bg-gray-700 mx-1" />
            <span className="text-xs text-gray-500 truncate max-w-32 hidden xl:block">{session.user.email}</span>
            <button onClick={() => supabase.auth.signOut()}
              className="text-xs text-gray-400 hover:text-white border border-gray-700 rounded px-2 py-1 transition-colors shrink-0">
              Sign out
            </button>
          </div>
        </div>

        {/* Mega menu — direct child of <nav>, escapes the scroll container */}
        {activeMenu && currentNav && currentNav.groups.length > 0 && (
          <div className="absolute top-14 flex shadow-2xl border border-gray-700 rounded-b-lg overflow-hidden z-50"
            style={{ left: menuLeft }}>

            {/* Left panel — groups */}
            <div className="bg-gray-800 w-52 py-2 shrink-0">
              <p className="px-4 py-1.5 text-xs font-semibold text-gray-500 uppercase tracking-widest">
                {activeMenu}
              </p>
              {currentNav.groups.map(g => (
                <button key={g.group}
                  onMouseEnter={() => setActiveGroup(g.group)}
                  className={`w-full text-left px-4 py-2 text-sm flex items-center justify-between transition-colors whitespace-nowrap ${
                    activeGroup === g.group
                      ? 'bg-gray-700 text-white'
                      : 'text-gray-300 hover:bg-gray-700 hover:text-white'
                  }`}>
                  {g.group}
                  <span className="text-gray-500 text-xs ml-3">›</span>
                </button>
              ))}
            </div>

            {/* Right panel — items, auto height, no internal scroll */}
            <div className="bg-gray-900 w-72 py-3">
              <p className="px-4 pb-1.5 text-xs font-semibold text-gray-500 uppercase tracking-widest">
                {activeGroup}
              </p>
              {currentGroupItems.map(mod => (
                <button key={mod.name}
                  onClick={() => navigate(mod.page)}
                  disabled={!mod.page}
                  className={`w-full text-left px-4 py-1.5 text-sm transition-colors whitespace-nowrap ${
                    mod.page
                      ? 'text-gray-200 hover:bg-gray-700 hover:text-white'
                      : 'text-gray-500 cursor-not-allowed'
                  }`}>
                  {mod.name}
                </button>
              ))}
            </div>
          </div>
        )}
      </nav>

      {activeMenu && <div className="fixed inset-0 z-40" onClick={closeMenu} />}

      {/* Breadcrumb + main */}
      <main className="pt-16 px-6 pb-6">
        <div className="max-w-7xl mx-auto">
          {/* Breadcrumb */}
          {currentPage && (
            <div className="flex items-center gap-1.5 text-xs text-gray-400 mb-4">
              <button onClick={() => rrNavigate('/')} className="hover:text-gray-700">Home</button>
              {breadcrumbSection && <>
                <span>›</span>
                <span className="text-gray-500">{breadcrumbSection}</span>
              </>}
              <span>›</span>
              <span className="text-gray-700 font-medium">{PAGE_LABELS[currentPage] || currentPage}</span>
            </div>
          )}
          {children}
        </div>
      </main>
    </div>
  )
}

export default function AppShell({ session, children }: { session: Session; children: React.ReactNode }) {
  return (
    <AppContextProvider>
      <AppShellInner session={session}>{children}</AppShellInner>
    </AppContextProvider>
  )
}
