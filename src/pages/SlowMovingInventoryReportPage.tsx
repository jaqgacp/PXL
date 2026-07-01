import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  qty_on_hand: number
  total_cost: number
  last_issue_date: string | null
  last_receipt_date: string | null
  items: { item_code: string; item_name: string } | null
  warehouses: { warehouse_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function SlowMovingInventoryReportPage() {
  const { companyId } = useAppCtx()
  const [thresholdDays, setThresholdDays] = useState(90)
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('stock_balances')
      .select('id,qty_on_hand,total_cost,last_issue_date,last_receipt_date,items(item_code,item_name),warehouses(warehouse_name)')
      .eq('company_id', companyId).gt('qty_on_hand', 0)
    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const now = Date.now()
  const daysSince = (d: string | null) => d ? Math.floor((now - new Date(d).getTime()) / (1000 * 60 * 60 * 24)) : Infinity
  const slowMoving = rows.filter(r => daysSince(r.last_issue_date) >= thresholdDays).sort((a, b) => daysSince(b.last_issue_date) - daysSince(a.last_issue_date))
  const totalValue = slowMoving.reduce((s, r) => s + r.total_cost, 0)

  const exportCSV = () => {
    const header = ['Item Code', 'Item Name', 'Warehouse', 'Qty on Hand', 'Value', 'Last Issue', 'Days Idle']
    const csvRows = slowMoving.map(r => [r.items?.item_code || '', r.items?.item_name || '', r.warehouses?.warehouse_name || '', r.qty_on_hand, r.total_cost.toFixed(2), r.last_issue_date || 'Never', daysSince(r.last_issue_date) === Infinity ? 'N/A' : daysSince(r.last_issue_date)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `slow-moving-inventory.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Slow Moving Inventory Report</h1><p className="text-sm text-gray-500 mt-0.5">On-hand items with no issue activity beyond the threshold</p></div>
        <button onClick={exportCSV} disabled={slowMoving.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <label className="text-xs text-gray-500">No activity for at least</label>
        <input type="number" value={thresholdDays} onChange={e => setThresholdDays(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-20" />
        <span className="text-xs text-gray-500">days</span>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <p className="text-xs text-gray-500 uppercase tracking-wide">Slow-Moving Inventory Value</p>
        <p className="text-2xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalValue)}</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Item</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Warehouse</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Qty on Hand</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Value</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Last Issue</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Days Idle</th>
            </tr></thead>
            <tbody>
              {slowMoving.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No slow-moving items found.'}</td></tr>
              ) : slowMoving.map(r => {
                const days = daysSince(r.last_issue_date)
                return (
                  <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="px-4 py-2 text-gray-700">{r.items?.item_code} — {r.items?.item_name}</td>
                    <td className="px-4 py-2 text-gray-500">{r.warehouses?.warehouse_name || '—'}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{r.qty_on_hand}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.total_cost)}</td>
                    <td className="px-4 py-2 text-gray-500">{r.last_issue_date || 'Never'}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-red-600 font-semibold">{days === Infinity ? 'N/A' : days}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
