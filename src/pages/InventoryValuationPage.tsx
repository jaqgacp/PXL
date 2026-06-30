import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type ValRow = {
  warehouse_id: string
  warehouse_code: string
  warehouse_name: string
  item_id: string
  item_code: string
  item_name: string
  uom_code: string
  costing_method: string
  qty_on_hand: number
  wac_unit_cost: number
  total_cost: number
  fifo_layers: number
  fifo_qty_remaining: number
  category_name: string
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'
const fmtQty = (n: number, d = 4) => n?.toLocaleString('en-PH', { minimumFractionDigits: 0, maximumFractionDigits: d }) ?? '0'
const METHOD: Record<string, string> = {
  weighted_average: 'WAC', fifo: 'FIFO', specific_identification: 'Specific ID'
}

export default function InventoryValuationPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<ValRow[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [whFilter, setWhFilter] = useState('all')
  const [methodFilter, setMethodFilter] = useState('all')
  const [groupBy, setGroupBy] = useState<'item' | 'warehouse' | 'category'>('item')
  const [warehouses, setWarehouses] = useState<{ id: string; code: string; name: string }[]>([])

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: sbData }, { data: layerData }] = await Promise.all([
      supabase.from('stock_balances').select(`
        warehouse_id, item_id, qty_on_hand, wac_unit_cost, total_cost,
        warehouses!inner(warehouse_code, warehouse_name, company_id),
        items!inner(item_code, description, costing_method,
          units_of_measure!inner(uom_code),
          item_categories!inner(category_name))
      `).eq('warehouses.company_id', companyId).gt('qty_on_hand', 0),
      supabase.from('inventory_cost_layers').select(
        'item_id, warehouse_id, qty_remaining'
      ).eq('company_id', companyId).eq('is_exhausted', false).gt('qty_remaining', 0),
    ])

    const layerMap: Record<string, { count: number; qty: number }> = {}
    for (const l of (layerData || []) as any[]) {
      const k = `${l.item_id}::${l.warehouse_id}`
      if (!layerMap[k]) layerMap[k] = { count: 0, qty: 0 }
      layerMap[k].count++
      layerMap[k].qty += Number(l.qty_remaining)
    }

    const list = ((sbData || []) as any[]).map(r => {
      const lk = `${r.item_id}::${r.warehouse_id}`
      return {
        warehouse_id: r.warehouse_id,
        warehouse_code: r.warehouses?.warehouse_code ?? '',
        warehouse_name: r.warehouses?.warehouse_name ?? '',
        item_id: r.item_id,
        item_code: r.items?.item_code ?? '',
        item_name: r.items?.description ?? '',
        uom_code: r.items?.units_of_measure?.uom_code ?? '',
        costing_method: r.items?.costing_method ?? 'weighted_average',
        category_name: r.items?.item_categories?.category_name ?? '',
        qty_on_hand: Number(r.qty_on_hand),
        wac_unit_cost: Number(r.wac_unit_cost),
        total_cost: Number(r.total_cost),
        fifo_layers: layerMap[lk]?.count ?? 0,
        fifo_qty_remaining: layerMap[lk]?.qty ?? 0,
      }
    })

    setRows(list)
    const whs = [...new Map(list.map(r => [r.warehouse_id, { id: r.warehouse_id, code: r.warehouse_code, name: r.warehouse_name }])).values()]
    setWarehouses(whs)
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  const visible = rows.filter(r => {
    if (whFilter !== 'all' && r.warehouse_id !== whFilter) return false
    if (methodFilter !== 'all' && r.costing_method !== methodFilter) return false
    const q = search.toLowerCase()
    return !q || r.item_name.toLowerCase().includes(q) || r.item_code.toLowerCase().includes(q) || r.category_name.toLowerCase().includes(q)
  })

  const totalValue = visible.reduce((s, r) => s + r.total_cost, 0)
  const totalQty = visible.reduce((s, r) => s + r.qty_on_hand, 0)

  // Group by logic
  const grouped = (() => {
    if (groupBy === 'item') return null
    const map: Record<string, { label: string; items: ValRow[]; total: number }> = {}
    for (const r of visible) {
      const key = groupBy === 'warehouse' ? r.warehouse_id : r.category_name
      const label = groupBy === 'warehouse' ? `${r.warehouse_code} — ${r.warehouse_name}` : r.category_name
      if (!map[key]) map[key] = { label, items: [], total: 0 }
      map[key].items.push(r)
      map[key].total += r.total_cost
    }
    return Object.values(map).sort((a, b) => b.total - a.total)
  })()

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Inventory Valuation</span>
      </div>
      <div className="px-5 py-4 space-y-3">
        {/* Summary KPIs */}
        <div className="grid grid-cols-4 gap-3">
          {[
            { label: 'Total Inventory Value', value: `₱ ${fmt(totalValue)}` },
            { label: 'WAC Items', value: rows.filter(r => r.costing_method === 'weighted_average').length.toString() },
            { label: 'FIFO Items', value: rows.filter(r => r.costing_method === 'fifo').length.toString() },
            { label: 'Specific ID Items', value: rows.filter(r => r.costing_method === 'specific_identification').length.toString() },
          ].map(k => (
            <div key={k.label} className="bg-white border border-gray-200 rounded-lg px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{k.label}</p>
              <p className="text-base font-semibold text-gray-900 mt-1 font-mono">{k.value}</p>
            </div>
          ))}
        </div>

        {/* Filters */}
        <div className="bg-white border border-gray-200 rounded-lg p-3 flex items-end gap-3 flex-wrap">
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Search</label>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Item / category…"
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs w-48 focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Warehouse</label>
            <select value={whFilter} onChange={e => setWhFilter(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Warehouses</option>
              {warehouses.map(w => <option key={w.id} value={w.id}>{w.code} — {w.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Costing Method</label>
            <select value={methodFilter} onChange={e => setMethodFilter(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Methods</option>
              <option value="weighted_average">WAC</option>
              <option value="fifo">FIFO</option>
              <option value="specific_identification">Specific ID</option>
            </select>
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Group By</label>
            <div className="flex rounded border border-gray-300 overflow-hidden">
              {(['item','warehouse','category'] as const).map(g => (
                <button key={g} onClick={() => setGroupBy(g)}
                  className={`px-2.5 py-1.5 text-xs font-medium ${groupBy === g ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
                  {g.charAt(0).toUpperCase() + g.slice(1)}
                </button>
              ))}
            </div>
          </div>
          <span className="text-xs text-gray-400 ml-auto">{visible.length} rows · ₱ {fmt(totalValue)}</span>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          {loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading…</div>
          ) : grouped ? (
            // Grouped view
            <div>
              {grouped.map(g => (
                <div key={g.label}>
                  <div className="bg-gray-50 border-b border-gray-200 px-4 py-2 flex items-center justify-between">
                    <span className="text-xs font-semibold text-gray-700">{g.label}</span>
                    <span className="text-xs font-mono font-semibold text-gray-900">₱ {fmt(g.total)}</span>
                  </div>
                  <table className="w-full text-xs">
                    <tbody className="divide-y divide-gray-100">
                      {g.items.map(r => (
                        <tr key={`${r.warehouse_id}::${r.item_id}`} className="hover:bg-gray-50/60">
                          <td className="px-4 py-1.5 font-mono text-gray-600 w-24">{r.item_code}</td>
                          <td className="px-4 py-1.5 text-gray-800">{r.item_name}</td>
                          <td className="px-4 py-1.5 text-[10px] text-gray-400">{METHOD[r.costing_method]}</td>
                          <td className="px-4 py-1.5 text-right font-mono text-gray-600">{fmtQty(r.qty_on_hand)} {r.uom_code}</td>
                          <td className="px-4 py-1.5 text-right font-mono text-gray-600">{fmt(r.wac_unit_cost)}</td>
                          <td className="px-4 py-1.5 text-right font-mono font-semibold text-gray-900">{fmt(r.total_cost)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ))}
              <div className="bg-gray-50 border-t-2 border-gray-300 px-4 py-2 flex justify-between">
                <span className="text-xs font-bold text-gray-700">TOTAL</span>
                <span className="text-sm font-bold font-mono text-gray-900">₱ {fmt(totalValue)}</span>
              </div>
            </div>
          ) : (
            // Flat view
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Warehouse','Item Code','Item Name','Category','Method','On Hand','Unit Cost (₱)','Total Value (₱)','FIFO Layers','FIFO Qty'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visible.length === 0 ? (
                    <tr><td colSpan={10} className="py-12 text-center text-gray-400">No inventory on hand</td></tr>
                  ) : visible.map(r => (
                    <tr key={`${r.warehouse_id}::${r.item_id}`} className="hover:bg-gray-50/60">
                      <td className="px-3 py-1.5 font-mono text-gray-600 text-[10px]">{r.warehouse_code}</td>
                      <td className="px-3 py-1.5 font-mono font-semibold text-gray-900">{r.item_code}</td>
                      <td className="px-3 py-1.5 text-gray-800 max-w-[140px] truncate">{r.item_name}</td>
                      <td className="px-3 py-1.5 text-gray-500 text-[10px]">{r.category_name}</td>
                      <td className="px-3 py-1.5">
                        <span className={`inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium ${r.costing_method === 'fifo' ? 'bg-blue-50 text-blue-700' : r.costing_method === 'specific_identification' ? 'bg-purple-50 text-purple-700' : 'bg-gray-100 text-gray-600'}`}>
                          {METHOD[r.costing_method]}
                        </span>
                      </td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-800">{fmtQty(r.qty_on_hand)} {r.uom_code}</td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-600">{fmt(r.wac_unit_cost)}</td>
                      <td className="px-3 py-1.5 text-right font-mono font-semibold text-gray-900">{fmt(r.total_cost)}</td>
                      <td className="px-3 py-1.5 text-center text-gray-500">{r.fifo_layers > 0 ? r.fifo_layers : '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-500">{r.fifo_layers > 0 ? fmtQty(r.fifo_qty_remaining) : '—'}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="bg-gray-50 border-t-2 border-gray-300">
                  <tr>
                    <td colSpan={7} className="px-3 py-2 text-right text-xs font-bold text-gray-700">TOTAL INVENTORY VALUE</td>
                    <td className="px-3 py-2 text-right font-mono font-bold text-gray-900">₱ {fmt(totalValue)}</td>
                    <td colSpan={2}></td>
                  </tr>
                </tfoot>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
