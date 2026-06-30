import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type TxRow = {
  id: string
  transaction_type: string
  transaction_date: string
  item_code: string
  item_name: string
  warehouse_code: string
  warehouse_name: string
  qty: number
  uom_code: string
  unit_cost: number
  total_cost: number
  qty_on_hand_after: number
  costing_method: string
  reference_doc_type: string | null
  lot_number: string | null
  serial_number: string | null
  created_at: string
}

const TX_COLOR: Record<string, string> = {
  receipt: 'bg-green-50 text-green-700',
  adjustment_in: 'bg-blue-50 text-blue-700',
  adjustment_out: 'bg-red-50 text-red-700',
  transfer_in: 'bg-teal-50 text-teal-700',
  transfer_out: 'bg-orange-50 text-orange-700',
  issue: 'bg-purple-50 text-purple-700',
  count_variance_in: 'bg-indigo-50 text-indigo-700',
  count_variance_out: 'bg-amber-50 text-amber-700',
}
const TX_LABEL: Record<string, string> = {
  receipt: 'Receipt', adjustment_in: 'Adj In', adjustment_out: 'Adj Out',
  transfer_in: 'Transfer In', transfer_out: 'Transfer Out', issue: 'Issue',
  count_variance_in: 'Count +', count_variance_out: 'Count −',
}
const fmt = (n: number, d = 2) => n?.toLocaleString('en-PH', { minimumFractionDigits: d, maximumFractionDigits: d }) ?? '0'

export default function InventoryMovementsPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<TxRow[]>([])
  const [loading, setLoading] = useState(false)
  const [warehouses, setWarehouses] = useState<{ id: string; warehouse_code: string; warehouse_name: string }[]>([])
  const [search, setSearch] = useState('')
  const [whFilter, setWhFilter] = useState('all')
  const [typeFilter, setTypeFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState(() => {
    const d = new Date(); d.setDate(1)
    return d.toISOString().slice(0, 10)
  })
  const [dateTo, setDateTo] = useState(() => new Date().toISOString().slice(0, 10))

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('inventory_transactions').select(`
      id, transaction_type, transaction_date, qty, unit_cost, total_cost,
      qty_on_hand_after, costing_method, reference_doc_type, lot_number, serial_number, created_at,
      warehouses!inner(warehouse_code, warehouse_name, company_id),
      items!inner(item_code, description, units_of_measure!inner(uom_code))
    `)
      .eq('warehouses.company_id', companyId)
      .gte('transaction_date', dateFrom)
      .lte('transaction_date', dateTo)
      .order('transaction_date', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(500)

    const list = ((data || []) as any[]).map(r => ({
      id: r.id,
      transaction_type: r.transaction_type,
      transaction_date: r.transaction_date,
      item_code: r.items?.item_code ?? '',
      item_name: r.items?.description ?? '',
      warehouse_code: r.warehouses?.warehouse_code ?? '',
      warehouse_name: r.warehouses?.warehouse_name ?? '',
      qty: Number(r.qty),
      uom_code: r.items?.units_of_measure?.uom_code ?? '',
      unit_cost: Number(r.unit_cost),
      total_cost: Number(r.total_cost),
      qty_on_hand_after: Number(r.qty_on_hand_after),
      costing_method: r.costing_method ?? '',
      reference_doc_type: r.reference_doc_type,
      lot_number: r.lot_number,
      serial_number: r.serial_number,
      created_at: r.created_at,
    }))

    setRows(list)
    const whs = [...new Map(list.map(r => [r.warehouse_code, { id: r.warehouse_code, warehouse_code: r.warehouse_code, warehouse_name: r.warehouse_name }])).values()]
    setWarehouses(whs)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { load() }, [load])

  const visible = rows.filter(r => {
    if (whFilter !== 'all' && r.warehouse_code !== whFilter) return false
    if (typeFilter !== 'all' && r.transaction_type !== typeFilter) return false
    const q = search.toLowerCase()
    return !q || r.item_name.toLowerCase().includes(q) || r.item_code.toLowerCase().includes(q)
  })

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Inventory Movements</span>
      </div>
      <div className="px-5 py-4 space-y-3">
        <div className="bg-white border border-gray-200 rounded-lg p-3 flex items-end gap-3 flex-wrap">
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">From</label>
            <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">To</label>
            <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Warehouse</label>
            <select value={whFilter} onChange={e => setWhFilter(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Warehouses</option>
              {warehouses.map(w => <option key={w.id} value={w.warehouse_code}>{w.warehouse_code} — {w.warehouse_name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Type</label>
            <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Types</option>
              {Object.entries(TX_LABEL).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Search</label>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Item…"
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs w-44 focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </div>
          <span className="text-xs text-gray-400 ml-auto">{visible.length} rows</span>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          {loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading…</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Date','Type','Item Code','Item Name','Warehouse','Qty','Unit Cost (₱)','Total Cost (₱)','On Hand After','Method','Lot / Serial','Ref'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visible.length === 0 ? (
                    <tr><td colSpan={12} className="py-12 text-center text-gray-400">No transactions in range</td></tr>
                  ) : visible.map(r => (
                    <tr key={r.id} className="hover:bg-gray-50/60">
                      <td className="px-3 py-1.5 font-mono text-gray-500">{r.transaction_date}</td>
                      <td className="px-3 py-1.5">
                        <span className={`inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium whitespace-nowrap ${TX_COLOR[r.transaction_type] || 'bg-gray-100 text-gray-500'}`}>
                          {TX_LABEL[r.transaction_type] || r.transaction_type}
                        </span>
                      </td>
                      <td className="px-3 py-1.5 font-mono font-semibold text-gray-900">{r.item_code}</td>
                      <td className="px-3 py-1.5 text-gray-800 max-w-[140px] truncate">{r.item_name}</td>
                      <td className="px-3 py-1.5 text-gray-500">{r.warehouse_code}</td>
                      <td className={`px-3 py-1.5 text-right font-mono font-semibold ${r.qty >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                        {r.qty >= 0 ? '+' : ''}{fmt(r.qty, 4)} {r.uom_code}
                      </td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-600">{fmt(r.unit_cost, 6)}</td>
                      <td className={`px-3 py-1.5 text-right font-mono font-semibold ${r.total_cost >= 0 ? 'text-gray-900' : 'text-red-700'}`}>
                        {fmt(r.total_cost)}
                      </td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-600">{fmt(r.qty_on_hand_after, 4)}</td>
                      <td className="px-3 py-1.5 text-[10px] text-gray-400">{r.costing_method === 'weighted_average' ? 'WAC' : r.costing_method === 'fifo' ? 'FIFO' : r.costing_method === 'specific_identification' ? 'SpecID' : '—'}</td>
                      <td className="px-3 py-1.5 font-mono text-gray-400 text-[10px]">{[r.lot_number, r.serial_number].filter(Boolean).join(' / ') || '—'}</td>
                      <td className="px-3 py-1.5 text-[10px] text-gray-400">{r.reference_doc_type || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
