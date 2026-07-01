import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

const LINKS = [
  { label: 'Balance Sheet', page: 'balance-sheet' },
  { label: 'Income Statement', page: 'income-statement' },
  { label: 'Statement of Cash Flows', page: 'statement-of-cash-flows' },
  { label: 'Trial Balance', page: 'trial-balance' },
  { label: 'General Ledger', page: 'general-ledger' },
  { label: 'AR Aging & Customer Ledger', page: 'ar-aging' },
  { label: 'AP Aging & Supplier Ledger', page: 'ap-aging' },
  { label: 'Bank Reconciliation', page: 'bank-reconciliation' },
  { label: 'Fixed Asset Register', page: 'asset-register' },
  { label: 'Inventory Valuation', page: 'inventory-valuation' },
  { label: 'Document Void Register', page: 'cas-document-void-register' },
  { label: 'Transaction Audit Log', page: 'cas-transaction-audit-log' },
]

export default function AuditSupportPackagePage() {
  const { companyId } = useAppCtx()
  const navigate = useNavigate()
  const [lockedPeriods, setLockedPeriods] = useState(0)
  const [openPeriods, setOpenPeriods] = useState(0)
  const [unreconciledBanks, setUnreconciledBanks] = useState(0)
  const [voidCount, setVoidCount] = useState(0)
  const [totalAssets, setTotalAssets] = useState(0)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ count: locked }, { count: open }, { data: bankAccounts }, { count: voids }, { data: coa }] = await Promise.all([
      supabase.from('fiscal_periods').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('is_locked', true),
      supabase.from('fiscal_periods').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('is_locked', false),
      supabase.from('bank_accounts').select('id').eq('company_id', companyId).eq('is_active', true),
      supabase.from('sales_invoices').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('status', 'cancelled'),
      supabase.from('chart_of_accounts').select('id,account_type').eq('company_id', companyId).eq('account_type', 'asset').eq('is_postable', true),
    ])

    setLockedPeriods(locked || 0)
    setOpenPeriods(open || 0)
    setUnreconciledBanks((bankAccounts || []).length)
    setVoidCount(voids || 0)
    setTotalAssets((coa || []).length)
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Audit Support Package</h1>
          <p className="text-sm text-gray-500 mt-0.5">Consolidated index of financial statements, ledgers &amp; audit trails for external audit</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print Index</button>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : (
        <>
          <div className="grid grid-cols-5 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Locked Periods</p><p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : lockedPeriods}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Open Periods</p><p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : openPeriods}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Active Bank Accounts</p><p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : unreconciledBanks}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Voided Sales Invoices</p><p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : voidCount}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Postable Asset Accounts</p><p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : totalAssets}</p></div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Audit Package Contents</h2></div>
            <div className="divide-y divide-gray-100">
              {LINKS.map(item => (
                <button key={item.page} onClick={() => navigate(`/${item.page}`)} className="w-full flex items-center justify-between px-4 py-3 text-sm hover:bg-gray-50 transition-colors text-left">
                  <span className="text-gray-900 font-medium">{item.label}</span>
                  <span className="text-gray-400">→</span>
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
