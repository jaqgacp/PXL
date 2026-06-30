import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type WarehouseSummary = {
  warehouse_id: string
  warehouse_name: string
  warehouse_code: string
  total_items: number
  total_qty: number
  total_value: number
}

type LowStockItem = {
  item_id: string
  item_code: string
  description: string
  warehouse_name: string
  qty_on_hand: number
  min_stock_level: number
  uom_code: string
}

type RecentTx = {
  id: string
  transaction_type: string
  transaction_date: string
  item_name: string
  warehouse_name: string
  qty: number
  total_cost: number
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'
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

export default function InventoryDashboardPage() {
  const { companyId } = useAppCtx()
  const [summaries, setSummaries] = useState<WarehouseSummary[]>([])
  const [lowStock, setLowStock] = useState<LowStockItem[]>([])
  const [recent, setRecent] = useState<RecentTx[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: sbData }, { data: txData }] = await Promise.all([
      supabase.from('stock_balances').select(`
        warehouse_id, qty_on_hand, total_cost,
        warehouses!inner(warehouse_code, warehouse_name, company_id),
        items!inner(item_code, description, min_stock_level, units_of_measure!inner(uom_code))
      `).eq('warehouses.company_id', companyId),
      supabase.from('inventory_transactions').select(`
        id, transaction_type, transaction_date, qty, total_cost,
        warehouses!inner(warehouse_name, company_id),
        items!inner(description)
      `).eq('warehouses.company_id', companyId)
        .order('created_at', { ascending: false }).limit(20),
    ])

    // Warehouse summaries
    const whMap: Record<string, WarehouseSummary> = {}
    for (const sb of (sbData || []) as any[]) {
      const wid = sb.warehouse_id
      if (!whMap[wid]) whMap[wid] = {
        warehouse_id: wid,
        warehouse_code: sb.warehouses?.warehouse_code ?? '',
        warehouse_name: sb.warehouses?.warehouse_name ?? '',
        total_items: 0, total_qty: 0, total_value: 0,
      }
      whMap[wid].total_items++
      whMap[wid].total_qty += Number(sb.qty_on_hand)
      whMap[wid].total_value += Number(sb.total_cost)
    }
    setSummaries(Object.values(whMap).sort((a, b) => a.warehouse_code.localeCompare(b.warehouse_code)))

    // Low stock alerts
    const low: LowStockItem[] = ((sbData || []) as any[])
      .filter((sb: any) => sb.items?.min_stock_level != null && Number(sb.qty_on_hand) <= Number(sb.items.min_stock_level))
      .map((sb: any) => ({
        item_id: sb.item_id,
        item_code: sb.items?.item_code ?? '',
        description: sb.items?.description ?? '',
        warehouse_name: sb.warehouses?.warehouse_name ?? '',
        qty_on_hand: Number(sb.qty_on_hand),
        min_stock_level: Number(sb.items?.min_stock_level ?? 0),
        uom_code: sb.items?.units_of_measure?.uom_code ?? '',
      }))
    setLowStock(low)

    // Recent transactions
    setRecent(((txData || []) as any[]).map(t => ({
      id: t.id,
      transaction_type: t.transaction_type,
      transaction_date: t.transaction_date,
      item_name: t.items?.description ?? '',
      warehouse_name: t.warehouses?.warehouse_name ?? '',
      qty: Number(t.qty),
      total_cost: Number(t.total_cost),
    })))

    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  const totalItems = [...new Set(summaries.flatMap(() => []))].length
  const totalValue = summaries.reduce((s, w) => s + w.total_value, 0)
  const totalWh = summaries.length

  if (loading) return <div className="p-8 text-xs text-gray-400">Loading…</div>

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Inventory Dashboard</span>
      </div>
      <div className="px-5 py-4 space-y-4">

        {/* KPIs */}
        <div className="grid grid-cols-3 gap-3">
          {[
            { label: 'Warehouses', value: totalWh.toString(), sub: 'Active locations' },
            { label: 'Stock Items', value: summaries.reduce((s, w) => s + w.total_items, 0).toString(), sub: 'Item-warehouse combinations' },
            { label: 'Total Inventory Value', value: `₱ ${fmt(totalValue)}`, sub: 'At costing method cost' },
          ].map(k => (
            <div key={k.label} className="bg-white border border-gray-200 rounded-lg px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{k.label}</p>
              <p className="text-xl font-semibold text-gray-900 mt-1 font-mono tabular-nums">{k.value}</p>
              <p className="text-[10px] text-gray-500 mt-0.5">{k.sub}</p>
            </div>
          ))}
        </div>

        {/* Warehouse breakdown */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Stock by Warehouse</p>
          </div>
          {summaries.length === 0 ? (
            <div className="py-10 text-center text-xs text-gray-400">No stock balances yet. Receive inventory to get started.</div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Code','Warehouse','Items','Total Qty','Inventory Value (₱)'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {summaries.map(w => (
                  <tr key={w.warehouse_id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{w.warehouse_code}</td>
                    <td className="px-3 py-2 text-gray-800">{w.warehouse_name}</td>
                    <td className="px-3 py-2 text-right font-mono text-gray-600">{w.total_items}</td>
                    <td className="px-3 py-2 text-right font-mono text-gray-600">{w.total_qty.toLocaleString('en-PH', { maximumFractionDigits: 4 })}</td>
                    <td className="px-3 py-2 text-right font-mono font-semibold text-gray-900">{fmt(w.total_value)}</td>
                  </tr>
                ))}
                <tr className="bg-gray-50 border-t border-gray-200 font-semibold">
                  <td colSpan={4} className="px-3 py-2 text-right text-xs text-gray-600">Total</td>
                  <td className="px-3 py-2 text-right font-mono text-gray-900">₱ {fmt(totalValue)}</td>
                </tr>
              </tbody>
            </table>
          )}
        </div>

        <div className="grid grid-cols-2 gap-4">
          {/* Low stock alerts */}
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Low Stock Alerts</p>
              {lowStock.length > 0 && (
                <span className="ml-auto inline-flex items-center px-2 py-0.5 rounded text-[10px] font-semibold bg-red-50 text-red-700">
                  {lowStock.length}
                </span>
              )}
            </div>
            {lowStock.length === 0 ? (
              <div className="py-8 text-center text-xs text-gray-400">All items above minimum stock</div>
            ) : (
              <div className="divide-y divide-gray-100 max-h-64 overflow-y-auto">
                {lowStock.map(item => (
                  <div key={`${item.item_id}-${item.warehouse_name}`} className="px-3 py-2">
                    <div className="flex items-start justify-between">
                      <div>
                        <p className="text-xs font-medium text-gray-900">{item.description}</p>
                        <p className="text-[10px] text-gray-400">{item.warehouse_name} · {item.item_code}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-xs font-mono font-semibold text-red-700">{item.qty_on_hand.toLocaleString()} {item.uom_code}</p>
                        <p className="text-[10px] text-gray-400">Min: {item.min_stock_level.toLocaleString()}</p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Recent transactions */}
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-3 py-2 border-b border-gray-100">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Recent Movements</p>
            </div>
            {recent.length === 0 ? (
              <div className="py-8 text-center text-xs text-gray-400">No transactions yet</div>
            ) : (
              <div className="divide-y divide-gray-100 max-h-64 overflow-y-auto">
                {recent.map(tx => (
                  <div key={tx.id} className="px-3 py-2 flex items-center gap-2">
                    <span className={`inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium whitespace-nowrap ${TX_COLOR[tx.transaction_type] || 'bg-gray-100 text-gray-600'}`}>
                      {tx.transaction_type.replace(/_/g, ' ')}
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-xs text-gray-800 truncate">{tx.item_name}</p>
                      <p className="text-[10px] text-gray-400">{tx.warehouse_name} · {tx.transaction_date}</p>
                    </div>
                    <span className={`text-xs font-mono font-semibold ${tx.qty >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                      {tx.qty >= 0 ? '+' : ''}{tx.qty.toLocaleString('en-PH', { maximumFractionDigits: 4 })}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
