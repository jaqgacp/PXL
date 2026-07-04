import { Fragment, useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type AuditLog = {
  id: string; table_name: string; record_id: string | null
  action: string; old_data: Record<string, unknown> | null; new_data: Record<string, unknown> | null
  changed_by: string | null; changed_at: string
}

const ACTION_COLORS: Record<string, string> = { INSERT: 'bg-green-50 text-green-700', UPDATE: 'bg-blue-50 text-blue-700', DELETE: 'bg-red-50 text-red-700' }

const TABLE_LABELS: Record<string, string> = {
  sales_invoices: 'Sales Invoices', receipts: 'Receipts', credit_memos: 'Credit Memos', debit_memos: 'Debit Memos',
  sales_orders: 'Sales Orders', delivery_receipts: 'Delivery Receipts',
  purchase_orders: 'Purchase Orders', vendor_bills: 'Vendor Bills', payment_vouchers: 'Payment Vouchers',
  cash_purchases: 'Cash Purchases', vendor_credits: 'Vendor Credits', purchase_returns: 'Purchase Returns',
  journal_entries: 'Journal Entries', bank_adjustments: 'Bank Adjustments', check_vouchers: 'Check Vouchers',
  petty_cash_vouchers: 'Petty Cash Vouchers', stock_adjustments: 'Stock Adjustments', stock_transfers: 'Stock Transfers',
  goods_issues: 'Goods Issues', fixed_assets: 'Fixed Assets', asset_disposals: 'Asset Disposals',
}

export default function CASTransactionAuditLogPage() {
  const { companyId } = useAppCtx()
  const [logs, setLogs] = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(false)
  const [filterTable, setFilterTable] = useState('')
  const [filterAction, setFilterAction] = useState('')
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [page, setPage] = useState(0)
  const PAGE_SIZE = 50

  const fetchLogs = async () => {
    if (!companyId) return
    setLoading(true)
    let query = supabase.from('sys_audit_logs').select('*').eq('company_id', companyId)
      .in('table_name', Object.keys(TABLE_LABELS))
      .order('changed_at', { ascending: false }).range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1)
    if (filterTable) query = query.eq('table_name', filterTable)
    if (filterAction) query = query.eq('action', filterAction)
    const { data } = await query
    setLogs((data as AuditLog[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { if (companyId) fetchLogs() }, [companyId, filterTable, filterAction, page])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Transaction Audit Log</h1>
        <p className="text-sm text-gray-500 mt-0.5">Change history for sales, purchasing, banking, inventory &amp; fixed asset transactions</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={filterTable} onChange={e => { setFilterTable(e.target.value); setPage(0) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="">All Documents</option>
          {Object.entries(TABLE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select value={filterAction} onChange={e => { setFilterAction(e.target.value); setPage(0) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="">All Actions</option>
          <option value="INSERT">Insert</option><option value="UPDATE">Update</option><option value="DELETE">Delete</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date/Time</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Document</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Action</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Record ID</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Changed By</th>
                <th className="w-10" />
              </tr>
            </thead>
            <tbody>
              {logs.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No transaction changes recorded.'}</td></tr>
              ) : logs.map(l => (
                <Fragment key={l.id}>
                  <tr className="border-b border-gray-100 hover:bg-gray-50 cursor-pointer" onClick={() => setExpandedId(expandedId === l.id ? null : l.id)}>
                    <td className="px-4 py-2 text-gray-700 text-xs">{new Date(l.changed_at).toLocaleString('en-PH')}</td>
                    <td className="px-4 py-2 text-gray-700">{TABLE_LABELS[l.table_name] || l.table_name}</td>
                    <td className="px-4 py-2"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${ACTION_COLORS[l.action]}`}>{l.action}</span></td>
                    <td className="px-4 py-2 text-gray-400 text-xs font-mono">{l.record_id?.slice(0, 8) || '—'}</td>
                    <td className="px-4 py-2 text-gray-500 text-xs font-mono">{l.changed_by?.slice(0, 8) || 'system'}</td>
                    <td className="px-2 py-2 text-gray-400 text-xs">{expandedId === l.id ? '▲' : '▼'}</td>
                  </tr>
                  {expandedId === l.id && (
                    <tr className="bg-gray-50/50">
                      <td colSpan={6} className="px-4 py-3">
                        <div className="grid grid-cols-2 gap-4 text-xs">
                          <div><p className="font-semibold text-gray-500 uppercase mb-1">Before</p><pre className="bg-white border border-gray-200 rounded p-2 overflow-auto max-h-48">{l.old_data ? JSON.stringify(l.old_data, null, 2) : '—'}</pre></div>
                          <div><p className="font-semibold text-gray-500 uppercase mb-1">After</p><pre className="bg-white border border-gray-200 rounded p-2 overflow-auto max-h-48">{l.new_data ? JSON.stringify(l.new_data, null, 2) : '—'}</pre></div>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="flex items-center justify-between">
        <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">← Previous</button>
        <span className="text-xs text-gray-400">Page {page + 1}</span>
        <button onClick={() => setPage(p => p + 1)} disabled={logs.length < PAGE_SIZE} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">Next →</button>
      </div>
    </div>
  )
}
