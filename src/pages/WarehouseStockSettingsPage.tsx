import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Warehouse = { id: string; warehouse_code: string; warehouse_name: string }
type Supplier = { id: string; supplier_code: string; supplier_name: string }
type SettingRow = {
  id: string | null
  item_id: string
  item_code: string
  item_name: string
  category_name: string
  uom_code: string
  costing_method: string
  qty_on_hand: number
  min_stock_level: string
  max_stock_level: string
  reorder_point: string
  reorder_qty: string
  lead_time_days: string
  preferred_supplier_id: string
  notes: string
  dirty: boolean
}

const CM: Record<string, string> = { weighted_average: 'WAC', fifo: 'FIFO', specific_identification: 'SpecID' }

export default function WarehouseStockSettingsPage() {
  const { companyId } = useAppCtx()
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [warehouseId, setWarehouseId] = useState('')
  const [rows, setRows] = useState<SettingRow[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState('')
  const [showLowOnly, setShowLowOnly] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState('')

  const loadMeta = useCallback(async () => {
    if (!companyId) return
    const [{ data: whs }, { data: sups }] = await Promise.all([
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('suppliers').select('id,supplier_code,supplier_name:registered_name').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
    ])
    setWarehouses((whs as Warehouse[]) || [])
    setSuppliers((sups as Supplier[]) || [])
  }, [companyId])

  useEffect(() => { loadMeta() }, [loadMeta])

  const loadWarehouse = useCallback(async (whId: string) => {
    if (!whId || !companyId) { setRows([]); return }
    setLoading(true)

    // Load all active inventory items for this company
    const { data: itemData } = await supabase.from('items').select(`
      id, item_code, description, costing_method,
      item_categories!inner(category_name),
      units_of_measure!inner(uom_code)
    `).eq('company_id', companyId).eq('is_active', true).eq('item_type', 'inventory_item').order('item_code')

    // Load existing settings for this warehouse
    const { data: settingsData } = await supabase.from('warehouse_item_settings')
      .select('*').eq('warehouse_id', whId).eq('company_id', companyId)

    // Load current stock balances
    const { data: balanceData } = await supabase.from('stock_balances')
      .select('item_id,qty_on_hand').eq('warehouse_id', whId)

    const settingsMap: Record<string, any> = {}
    for (const s of (settingsData || []) as any[]) settingsMap[s.item_id] = s

    const balanceMap: Record<string, number> = {}
    for (const b of (balanceData || []) as any[]) balanceMap[b.item_id] = Number(b.qty_on_hand)

    const list: SettingRow[] = ((itemData || []) as any[]).map(item => {
      const s = settingsMap[item.id]
      return {
        id: s?.id ?? null,
        item_id: item.id,
        item_code: item.item_code,
        item_name: item.description,
        category_name: item.item_categories?.category_name ?? '',
        uom_code: item.units_of_measure?.uom_code ?? '',
        costing_method: item.costing_method ?? 'weighted_average',
        qty_on_hand: balanceMap[item.id] ?? 0,
        min_stock_level: s?.min_stock_level?.toString() ?? '',
        max_stock_level: s?.max_stock_level?.toString() ?? '',
        reorder_point: s?.reorder_point?.toString() ?? '',
        reorder_qty: s?.reorder_qty?.toString() ?? '',
        lead_time_days: s?.lead_time_days?.toString() ?? '',
        preferred_supplier_id: s?.preferred_supplier_id ?? '',
        notes: s?.notes ?? '',
        dirty: false,
      }
    })
    setRows(list)
    setLoading(false)
  }, [companyId])

  const onWhChange = (id: string) => { setWarehouseId(id); loadWarehouse(id) }

  const updateRow = (idx: number, field: keyof SettingRow, value: string) => {
    setRows(p => p.map((r, i) => i === idx ? { ...r, [field]: value, dirty: true } : r))
  }

  const save = async () => {
    if (!companyId || !warehouseId) return
    const dirtyRows = rows.filter(r => r.dirty)
    if (dirtyRows.length === 0) return
    setSaving(true); setError(''); setSaved(false)

    const toUpsert = dirtyRows.map(r => ({
      ...(r.id ? { id: r.id } : {}),
      company_id: companyId,
      warehouse_id: warehouseId,
      item_id: r.item_id,
      min_stock_level: r.min_stock_level !== '' ? Number(r.min_stock_level) : 0,
      max_stock_level: r.max_stock_level !== '' ? Number(r.max_stock_level) : null,
      reorder_point: r.reorder_point !== '' ? Number(r.reorder_point) : null,
      reorder_qty: r.reorder_qty !== '' ? Number(r.reorder_qty) : null,
      lead_time_days: r.lead_time_days !== '' ? Number(r.lead_time_days) : null,
      preferred_supplier_id: r.preferred_supplier_id || null,
      notes: r.notes || null,
    }))

    const { error: e } = await supabase.from('warehouse_item_settings').upsert(toUpsert, { onConflict: 'warehouse_id,item_id' })
    setSaving(false)
    if (e) { setError(e.message); return }
    setSaved(true)
    setRows(p => p.map(r => ({ ...r, dirty: false })))
    loadWarehouse(warehouseId)
    setTimeout(() => setSaved(false), 3000)
  }

  const visible = rows.filter(r => {
    const q = search.toLowerCase()
    const matchSearch = !q || r.item_code.toLowerCase().includes(q) || r.item_name.toLowerCase().includes(q) || r.category_name.toLowerCase().includes(q)
    const matchLow = !showLowOnly || (r.min_stock_level !== '' && r.qty_on_hand <= Number(r.min_stock_level))
    return matchSearch && matchLow
  })

  const dirtyCount = rows.filter(r => r.dirty).length

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Warehouse Stock Settings</span>
        {dirtyCount > 0 && (
          <span className="text-xs bg-amber-100 text-amber-700 px-2 py-0.5 rounded font-medium">{dirtyCount} unsaved</span>
        )}
        <div className="ml-auto flex gap-2">
          {dirtyCount > 0 && (
            <button onClick={save} disabled={saving}
              className="px-3 py-1.5 bg-gray-900 text-white rounded text-xs font-medium hover:bg-gray-800 disabled:opacity-40">
              {saving ? 'Saving…' : `Save ${dirtyCount} Change${dirtyCount > 1 ? 's' : ''}`}
            </button>
          )}
        </div>
      </div>

      <div className="px-5 py-4 space-y-3">
        {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
        {saved && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">Settings saved.</div>}

        <div className="bg-white border border-gray-200 rounded-lg p-3 flex items-end gap-3 flex-wrap">
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Warehouse *</label>
            <select value={warehouseId} onChange={e => onWhChange(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs w-56 focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="">— Select Warehouse —</option>
              {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Search</label>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Item / category…"
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs w-48 focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </div>
          <label className="flex items-center gap-1.5 cursor-pointer select-none text-xs text-gray-600 mb-0.5">
            <input type="checkbox" checked={showLowOnly} onChange={e => setShowLowOnly(e.target.checked)} className="rounded" />
            Low stock only
          </label>
          {warehouseId && <span className="text-xs text-gray-400 ml-auto">{visible.length} items</span>}
        </div>

        <div className="bg-amber-50 border border-amber-200 rounded-lg px-4 py-2.5 text-xs text-amber-800">
          Settings here are per-warehouse. Min Stock Level triggers low-stock alerts on the Inventory Dashboard.
          Changes are saved in bulk — click <strong>Save</strong> when done editing.
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          {!warehouseId ? (
            <div className="py-16 text-center text-xs text-gray-400">Select a warehouse to configure stock settings</div>
          ) : loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading…</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Item','Category','Method','On Hand','Min Stock','Max Stock','Reorder Point','Reorder Qty','Lead Time (days)','Preferred Supplier'].map(h => (
                      <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visible.length === 0 ? (
                    <tr><td colSpan={10} className="py-12 text-center text-gray-400">No items</td></tr>
                  ) : visible.map((r) => {
                    const idx = rows.findIndex(x => x.item_id === r.item_id)
                    const isLow = r.min_stock_level !== '' && r.qty_on_hand <= Number(r.min_stock_level)
                    return (
                      <tr key={r.item_id} className={`${r.dirty ? 'bg-blue-50/40' : ''} ${isLow ? 'bg-red-50/30' : ''} hover:bg-gray-50/60`}>
                        <td className="px-3 py-1.5">
                          <p className="font-semibold text-gray-900">{r.item_code}</p>
                          <p className="text-[10px] text-gray-400 max-w-[160px] truncate">{r.item_name}</p>
                        </td>
                        <td className="px-3 py-1.5 text-gray-500 text-[10px]">{r.category_name}</td>
                        <td className="px-3 py-1.5">
                          <span className="text-[10px] text-gray-400">{CM[r.costing_method] ?? r.costing_method}</span>
                        </td>
                        <td className={`px-3 py-1.5 text-right font-mono font-semibold ${isLow ? 'text-red-700' : 'text-gray-800'}`}>
                          {r.qty_on_hand.toLocaleString('en-PH', { maximumFractionDigits: 4 })} {r.uom_code}
                          {isLow && <span className="ml-1 text-[9px] text-red-600 font-bold">LOW</span>}
                        </td>
                        {(['min_stock_level','max_stock_level','reorder_point','reorder_qty'] as const).map(field => (
                          <td key={field} className="px-3 py-1.5">
                            <input type="number" min={0} step={0.0001} value={(r as any)[field]}
                              onChange={e => updateRow(idx, field, e.target.value)}
                              className="border border-gray-200 rounded px-2 py-0.5 text-xs font-mono text-right w-20 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                          </td>
                        ))}
                        <td className="px-3 py-1.5">
                          <input type="number" min={0} step={1} value={r.lead_time_days}
                            onChange={e => updateRow(idx, 'lead_time_days', e.target.value)}
                            className="border border-gray-200 rounded px-2 py-0.5 text-xs font-mono text-right w-16 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                        </td>
                        <td className="px-3 py-1.5">
                          <select value={r.preferred_supplier_id}
                            onChange={e => updateRow(idx, 'preferred_supplier_id', e.target.value)}
                            className="border border-gray-200 rounded px-1.5 py-0.5 text-[10px] w-40 focus:outline-none focus:ring-1 focus:ring-gray-900">
                            <option value="">— None —</option>
                            {suppliers.map(s => <option key={s.id} value={s.id}>{s.supplier_name}</option>)}
                          </select>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
