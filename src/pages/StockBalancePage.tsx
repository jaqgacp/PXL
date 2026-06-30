import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type StockRow = {
  id: string
  warehouse_id: string
  warehouse_code: string
  warehouse_name: string
  item_id: string
  item_code: string
  item_name: string
  uom_code: string
  costing_method: string
  qty_on_hand: number
  qty_reserved: number
  qty_available: number
  wac_unit_cost: number
  total_cost: number
  min_stock_level: number | null
  last_receipt_date: string | null
  last_issue_date: string | null
}

type CostLayer = {
  id: string; layer_date: string; lot_number: string | null; serial_number: string | null
  original_qty: number; qty_remaining: number; unit_cost: number; is_exhausted: boolean
  reference_doc_type: string | null
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'
const fmtQty = (n: number) => n?.toLocaleString('en-PH', { maximumFractionDigits: 4 }) ?? '0'
const METHOD_LABEL: Record<string, string> = {
  weighted_average: 'WAC', fifo: 'FIFO', specific_identification: 'Specific ID'
}

export default function StockBalancePage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<StockRow[]>([])
  const [warehouses, setWarehouses] = useState<{ id: string; warehouse_code: string; warehouse_name: string }[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [whFilter, setWhFilter] = useState('all')
  const [selected, setSelected] = useState<StockRow | null>(null)
  const [layers, setLayers] = useState<CostLayer[]>([])
  const [layersLoading, setLayersLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('stock_balances').select(`
      id, warehouse_id, qty_on_hand, qty_reserved, total_cost, wac_unit_cost,
      last_receipt_date, last_issue_date,
      warehouses!inner(warehouse_code, warehouse_name, company_id),
      items!inner(item_code, description, costing_method, min_stock_level,
        units_of_measure!inner(uom_code))
    `).eq('warehouses.company_id', companyId).order('warehouses.warehouse_code')

    const list = ((data || []) as any[]).map(r => ({
      id: r.id,
      warehouse_id: r.warehouse_id,
      warehouse_code: r.warehouses?.warehouse_code ?? '',
      warehouse_name: r.warehouses?.warehouse_name ?? '',
      item_id: r.item_id,
      item_code: r.items?.item_code ?? '',
      item_name: r.items?.description ?? '',
      uom_code: r.items?.units_of_measure?.uom_code ?? '',
      costing_method: r.items?.costing_method ?? 'weighted_average',
      qty_on_hand: Number(r.qty_on_hand),
      qty_reserved: Number(r.qty_reserved),
      qty_available: Number(r.qty_on_hand) - Number(r.qty_reserved),
      wac_unit_cost: Number(r.wac_unit_cost),
      total_cost: Number(r.total_cost),
      min_stock_level: r.items?.min_stock_level != null ? Number(r.items.min_stock_level) : null,
      last_receipt_date: r.last_receipt_date,
      last_issue_date: r.last_issue_date,
    }))

    setRows(list)
    const whs = [...new Map(list.map(r => [r.warehouse_id, { id: r.warehouse_id, warehouse_code: r.warehouse_code, warehouse_name: r.warehouse_name }])).values()]
    setWarehouses(whs)
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  const openDetail = async (row: StockRow) => {
    setSelected(row)
    setLayersLoading(true)
    const { data } = await supabase.from('inventory_cost_layers')
      .select('id,layer_date,lot_number,serial_number,original_qty,qty_remaining,unit_cost,is_exhausted,reference_doc_type')
      .eq('item_id', row.item_id).eq('warehouse_id', row.warehouse_id)
      .order('layer_date').order('id')
    setLayers((data as CostLayer[]) || [])
    setLayersLoading(false)
  }

  const visible = rows.filter(r => {
    if (whFilter !== 'all' && r.warehouse_id !== whFilter) return false
    const q = search.toLowerCase()
    return !q || r.item_name.toLowerCase().includes(q) || r.item_code.toLowerCase().includes(q)
  })

  if (selected) return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <button onClick={() => setSelected(null)} className="text-xs text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">{selected.item_code} — {selected.item_name}</span>
        <span className="text-[10px] px-2 py-0.5 rounded bg-gray-100 text-gray-600">{METHOD_LABEL[selected.costing_method]}</span>
      </div>
      <div className="px-5 py-4 max-w-4xl space-y-4">
        <div className="grid grid-cols-4 gap-3">
          {[
            { label: 'On Hand', value: `${fmtQty(selected.qty_on_hand)} ${selected.uom_code}` },
            { label: 'Available', value: `${fmtQty(selected.qty_available)} ${selected.uom_code}` },
            { label: 'Unit Cost', value: `₱ ${fmt(selected.wac_unit_cost)}` },
            { label: 'Total Value', value: `₱ ${fmt(selected.total_cost)}` },
          ].map(k => (
            <div key={k.label} className="bg-white border border-gray-200 rounded-lg px-3 py-2.5">
              <p className="text-[10px] text-gray-400 font-semibold uppercase tracking-wide">{k.label}</p>
              <p className="text-sm font-semibold text-gray-900 mt-1 font-mono">{k.value}</p>
            </div>
          ))}
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">
              Cost Layers — {METHOD_LABEL[selected.costing_method]}
              {selected.costing_method === 'weighted_average' && <span className="ml-2 text-gray-400 normal-case font-normal">(layers shown for audit trail only)</span>}
            </p>
          </div>
          {layersLoading ? (
            <div className="py-8 text-center text-xs text-gray-400">Loading layers…</div>
          ) : layers.length === 0 ? (
            <div className="py-8 text-center text-xs text-gray-400">No cost layers</div>
          ) : (
            <div className="overflow-y-auto max-h-72">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200 sticky top-0">
                  <tr>{['Date','Ref Type','Lot','Serial','Original Qty','Remaining','Unit Cost (₱)','Status'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {layers.map(l => (
                    <tr key={l.id} className={`hover:bg-gray-50/60 ${l.is_exhausted ? 'opacity-40' : ''}`}>
                      <td className="px-3 py-1.5 font-mono text-gray-600">{l.layer_date}</td>
                      <td className="px-3 py-1.5 text-gray-500">{l.reference_doc_type || '—'}</td>
                      <td className="px-3 py-1.5 font-mono text-gray-600">{l.lot_number || '—'}</td>
                      <td className="px-3 py-1.5 font-mono text-gray-600">{l.serial_number || '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-600">{fmtQty(l.original_qty)}</td>
                      <td className="px-3 py-1.5 text-right font-mono font-semibold text-gray-900">{fmtQty(l.qty_remaining)}</td>
                      <td className="px-3 py-1.5 text-right font-mono text-gray-800">{fmt(l.unit_cost)}</td>
                      <td className="px-3 py-1.5">
                        <span className={`inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium ${l.is_exhausted ? 'bg-gray-100 text-gray-400' : 'bg-green-50 text-green-700'}`}>
                          {l.is_exhausted ? 'Exhausted' : 'Active'}
                        </span>
                      </td>
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

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Stock Balance</span>
      </div>
      <div className="px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2 flex-wrap">
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search item…"
              className="border border-gray-200 rounded px-2.5 py-1 text-xs w-56 focus:outline-none focus:ring-1 focus:ring-gray-900" />
            <select value={whFilter} onChange={e => setWhFilter(e.target.value)}
              className="border border-gray-200 rounded px-2.5 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Warehouses</option>
              {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}
            </select>
            <span className="text-xs text-gray-400 ml-auto">{visible.length} rows</span>
          </div>
          {loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading…</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Warehouse','Item Code','Item Name','Method','On Hand','Available','Unit Cost (₱)','Total Value (₱)','Last Receipt','Last Issue'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visible.length === 0 ? (
                    <tr><td colSpan={10} className="py-12 text-center text-gray-400">No stock records found</td></tr>
                  ) : visible.map(r => (
                    <tr key={r.id}
                      className={`hover:bg-gray-50/60 cursor-pointer ${r.min_stock_level != null && r.qty_on_hand <= r.min_stock_level ? 'bg-red-50/30' : ''}`}
                      onClick={() => openDetail(r)}>
                      <td className="px-3 py-2 font-mono text-gray-600">{r.warehouse_code}</td>
                      <td className="px-3 py-2 font-mono font-semibold text-gray-900">{r.item_code}</td>
                      <td className="px-3 py-2 text-gray-800 max-w-[160px] truncate">{r.item_name}</td>
                      <td className="px-3 py-2 text-gray-500 text-[10px]">{METHOD_LABEL[r.costing_method]}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-800">
                        {fmtQty(r.qty_on_hand)} <span className="text-gray-400">{r.uom_code}</span>
                        {r.min_stock_level != null && r.qty_on_hand <= r.min_stock_level &&
                          <span className="ml-1 text-red-600 font-bold" title="Below minimum">!</span>}
                      </td>
                      <td className="px-3 py-2 text-right font-mono text-gray-600">{fmtQty(r.qty_available)}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-600">{fmt(r.wac_unit_cost)}</td>
                      <td className="px-3 py-2 text-right font-mono font-semibold text-gray-900">{fmt(r.total_cost)}</td>
                      <td className="px-3 py-2 font-mono text-gray-400">{r.last_receipt_date || '—'}</td>
                      <td className="px-3 py-2 font-mono text-gray-400">{r.last_issue_date || '—'}</td>
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
