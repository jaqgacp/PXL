import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowRight, PackageCheck, Printer } from 'lucide-react'
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

type AuditPackageResult = {
  snapshot_id?: string
  snapshot_version?: number
  source_hash?: string
  row_count?: number
}

const dateInput = (date: Date) => date.toISOString().slice(0, 10)
const monthStart = () => {
  const now = new Date()
  return dateInput(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)))
}

export default function AuditSupportPackagePage() {
  const { companyId } = useAppCtx()
  const navigate = useNavigate()
  const [dateFrom, setDateFrom] = useState(monthStart())
  const [dateTo, setDateTo] = useState(dateInput(new Date()))
  const [lockedPeriods, setLockedPeriods] = useState(0)
  const [openPeriods, setOpenPeriods] = useState(0)
  const [unreconciledBanks, setUnreconciledBanks] = useState(0)
  const [voidCount, setVoidCount] = useState(0)
  const [totalAssets, setTotalAssets] = useState(0)
  const [loading, setLoading] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [packageResult, setPackageResult] = useState<AuditPackageResult | null>(null)
  const [packageError, setPackageError] = useState('')

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

  const generatePackage = async () => {
    if (!companyId) return
    if (!dateFrom || !dateTo || dateFrom > dateTo) {
      setPackageError('Enter a valid date range.')
      return
    }

    setGenerating(true)
    setPackageError('')
    setPackageResult(null)

    const fileName = `cas-audit-package-${dateFrom}-to-${dateTo}.json`
    const { data, error } = await supabase.rpc('fn_snapshot_cas_audit_package', {
      p_company_id: companyId,
      p_date_from: dateFrom,
      p_date_to: dateTo,
      p_file_name: fileName,
    })

    setGenerating(false)

    if (error) {
      setPackageError(error.message)
      return
    }

    setPackageResult((data || {}) as AuditPackageResult)
    await load()
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Audit Support Package</h1>
          <p className="text-sm text-gray-500 mt-0.5">Consolidated index of financial statements, ledgers &amp; audit trails for external audit</p>
        </div>
        <button onClick={() => window.print()} className="inline-flex items-center gap-2 border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
          <Printer className="h-4 w-4" />
          Print Index
        </button>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : (
        <>
          <div className="bg-white border border-gray-200 rounded-lg p-4">
            <div className="flex flex-wrap items-end gap-3">
              <div className="min-w-[160px]">
                <label className="block text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">Date From</label>
                <input
                  type="date"
                  value={dateFrom}
                  onChange={e => setDateFrom(e.target.value)}
                  className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
                />
              </div>
              <div className="min-w-[160px]">
                <label className="block text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">Date To</label>
                <input
                  type="date"
                  value={dateTo}
                  onChange={e => setDateTo(e.target.value)}
                  className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
                />
              </div>
              <button
                onClick={generatePackage}
                disabled={generating}
                className="inline-flex items-center gap-2 bg-gray-900 text-white px-3 py-2 rounded-md text-sm disabled:opacity-60 hover:bg-gray-800"
              >
                <PackageCheck className="h-4 w-4" />
                {generating ? 'Generating' : 'Generate Package'}
              </button>
              {packageResult && (
                <div className="text-xs text-gray-600">
                  <span className="font-medium text-gray-900">v{packageResult.snapshot_version}</span>
                  <span className="mx-2">Hash {packageResult.source_hash?.slice(0, 12)}</span>
                  <span>{packageResult.row_count || 0} evidence rows</span>
                </div>
              )}
            </div>
            {packageError && <div className="mt-3 text-sm text-red-700 bg-red-50 border border-red-200 rounded-md px-3 py-2">{packageError}</div>}
          </div>

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
                  <ArrowRight className="h-4 w-4 text-gray-400" />
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
