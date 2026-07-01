import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const BOOKS = [
  { group: 'Journals', items: [
    { label: 'General Journal', page: 'books-general-journal' },
    { label: 'Sales Journal', page: 'books-sales-journal' },
    { label: 'Cash Sales Journal', page: 'books-cash-sales-journal' },
    { label: 'Purchase Journal', page: 'books-purchase-journal' },
    { label: 'Cash Purchases Journal', page: 'books-cash-purchases-journal' },
    { label: 'Cash Receipts Book', page: 'books-cash-receipts' },
    { label: 'Cash Disbursements Book', page: 'books-cash-disbursements' },
  ]},
  { group: 'Ledgers', items: [
    { label: 'General Ledger Book', page: 'general-ledger' },
    { label: 'AR Subsidiary Ledger', page: 'ar-aging' },
    { label: 'AP Subsidiary Ledger', page: 'ap-aging' },
    { label: 'Inventory Subsidiary Ledger', page: 'inventory-movements' },
    { label: 'Fixed Asset Register', page: 'asset-register' },
  ]},
]

export default function BooksDashboardPage() {
  const { companyId } = useAppCtx()
  const navigate = useNavigate()
  const now = new Date()
  const [postedJeCount, setPostedJeCount] = useState(0)
  const [totalDebits, setTotalDebits] = useState(0)
  const [openPeriods, setOpenPeriods] = useState(0)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`
    const endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split('T')[0]

    const [{ count: jeCount }, { data: jeSums }, { count: periodCount }] = await Promise.all([
      supabase.from('journal_entries').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('status', 'posted').gte('je_date', startDate).lte('je_date', endDate),
      supabase.from('journal_entries').select('total_debit').eq('company_id', companyId).eq('status', 'posted').gte('je_date', startDate).lte('je_date', endDate),
      supabase.from('fiscal_periods').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('is_locked', false),
    ])

    setPostedJeCount(jeCount || 0)
    setTotalDebits(((jeSums || []) as { total_debit: number }[]).reduce((s, r) => s + Number(r.total_debit), 0))
    setOpenPeriods(periodCount || 0)
    setLoading(false)
  }, [companyId, now])

  useEffect(() => { load() }, [load])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Books Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">BIR-mandated Books of Accounts — journals, ledgers &amp; registers</p>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Posted JEs — This Month</p>
              <p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : postedJeCount}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Total Debits — This Month</p>
              <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{loading ? '—' : fmtNum(totalDebits)}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Open Fiscal Periods</p>
              <p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : openPeriods}</p>
            </div>
          </div>

          {BOOKS.map(section => (
            <div key={section.group} className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">{section.group}</h2></div>
              <div className="divide-y divide-gray-100">
                {section.items.map(item => (
                  <button key={item.page} onClick={() => navigate(`/${item.page}`)} className="w-full flex items-center justify-between px-4 py-3 text-sm hover:bg-gray-50 transition-colors text-left">
                    <span className="text-gray-900 font-medium">{item.label}</span>
                    <span className="text-gray-400">→</span>
                  </button>
                ))}
              </div>
            </div>
          ))}
        </>
      )}
    </div>
  )
}
