import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { transactionHeaderClass, transactionSegmentButtonClass } from '@/lib/transactionWorkspace'

type Warehouse = { id: string; warehouse_code: string; warehouse_name: string }
type Item = { id: string; item_code: string; description: string; costing_method: string; uom_code: string }
type COA = { id: string; account_code: string; account_name: string }
type AdjLine = {
  item_id: string; item_code: string; item_name: string; uom_code: string; costing_method: string
  qty_before: number; qty_adjusted: string; lot_number: string; serial_number: string; gl_offset_account_id: string
}
type Adjustment = {
  id: string; adjustment_number: string; adjustment_date: string; reason: string
  warehouse_name: string; status: string; notes: string | null
}

const REASONS = [
  { value: 'initial_load', label: 'Initial Stock Load' },
  { value: 'correction', label: 'Book Correction' },
  { value: 'shrinkage', label: 'Shrinkage / Pilferage' },
  { value: 'damage', label: 'Damaged Goods' },
  { value: 'expired', label: 'Expired Stock' },
  { value: 'write_off', label: 'Write-Off' },
  { value: 'donation', label: 'Donation' },
  { value: 'other', label: 'Other' },
]

export default function StockAdjustmentPage() {
  const { companyId, branchId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [tab, setTab] = useState<'new' | 'history'>('new')
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [items, setItems] = useState<Item[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [history, setHistory] = useState<Adjustment[]>([])
  const [warehouseId, setWarehouseId] = useState('')
  const [adjDate, setAdjDate] = useState(today)
  const [reason, setReason] = useState('correction')
  const [notes, setNotes] = useState('')
  const [lines, setLines] = useState<AdjLine[]>([])
  const [saving, setSaving] = useState(false)
  const [posting, setPosting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [pendingId, setPendingId] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: whs }, { data: itemData }, { data: coaData }, { data: adjData }] = await Promise.all([
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('items').select('id,item_code,description,costing_method,units_of_measure!inner(uom_code)').eq('company_id', companyId).eq('is_active', true).eq('item_type', 'inventory_item').order('item_code'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
      supabase.from('stock_adjustments').select(`id,adjustment_number,adjustment_date,reason,status,notes,warehouses!inner(warehouse_name)`).eq('company_id', companyId).order('adjustment_date', { ascending: false }).limit(50),
    ])
    setWarehouses((whs as Warehouse[]) || [])
    setItems(((itemData || []) as any[]).map(i => ({ id: i.id, item_code: i.item_code, description: i.description, costing_method: i.costing_method || 'weighted_average', uom_code: i.units_of_measure?.uom_code || '' })))
    setCoa((coaData as COA[]) || [])
    setHistory(((adjData || []) as any[]).map(a => ({ id: a.id, adjustment_number: a.adjustment_number, adjustment_date: a.adjustment_date, reason: a.reason, warehouse_name: a.warehouses?.warehouse_name ?? '', status: a.status, notes: a.notes })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  const addLine = (itemId: string) => {
    const item = items.find(i => i.id === itemId)
    if (!item || lines.find(l => l.item_id === itemId)) return
    setLines(p => [...p, {
      item_id: itemId, item_code: item.item_code, item_name: item.description,
      uom_code: item.uom_code, costing_method: item.costing_method,
      qty_before: 0, qty_adjusted: '0', lot_number: '', serial_number: '', gl_offset_account_id: '',
    }])
  }

  const updateLine = (idx: number, k: keyof AdjLine, v: string) =>
    setLines(p => p.map((l, i) => i === idx ? { ...l, [k]: v } : l))

  const removeLine = (idx: number) => setLines(p => p.filter((_, i) => i !== idx))

  const saveDraft = async () => {
    if (!companyId || !warehouseId) { setError('Select a warehouse'); return }
    if (lines.length === 0) { setError('Add at least one item'); return }
    setSaving(true); setError(''); setSuccess('')
    const { data: adjData, error: e1 } = await supabase.from('stock_adjustments').insert({
      company_id: companyId, branch_id: branchId || null,
      warehouse_id: warehouseId,
      adjustment_number: 'PENDING',
      adjustment_date: adjDate, reason, notes: notes || null, status: 'draft',
    }).select().single()
    if (e1 || !adjData) { setSaving(false); setError(e1?.message || 'Failed to save'); return }

    const linesPayload = lines.map(l => ({
      adjustment_id: (adjData as any).id, company_id: companyId, item_id: l.item_id,
      qty_before: l.qty_before, qty_adjusted: Number(l.qty_adjusted),
      qty_after: l.qty_before + Number(l.qty_adjusted),
      lot_number: l.lot_number || null, serial_number: l.serial_number || null,
      gl_offset_account_id: l.gl_offset_account_id || null,
    }))
    const { error: e2 } = await supabase.from('stock_adjustment_lines').insert(linesPayload)
    setSaving(false)
    if (e2) { setError(e2.message); return }
    setPendingId((adjData as any).id)
    setSuccess(`Draft saved as ${(adjData as any).adjustment_number}. Ready to post.`)
  }

  const post = async () => {
    if (!pendingId) return
    setPosting(true); setError(''); setSuccess('')
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'INV_ADJ', p_source_doc_id: pendingId })
    if (previewError) {
      setPosting(false)
      setError(`Stock Adjustment is not ready to post: ${previewError.message}`)
      return
    }
    const { error: e } = await supabase.rpc('fn_post_stock_adjustment', { p_adjustment_id: pendingId })
    setPosting(false)
    if (e) { setError(e.message); return }
    setSuccess('Adjustment posted. Stock balances and GL updated.')
    setPendingId(null); setLines([]); setNotes('')
    load()
  }

  return (
    <div>
      <div className={transactionHeaderClass('inventory')}>
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Stock Adjustment</span>
        <div className="ml-auto flex gap-1">
          {(['new','history'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={transactionSegmentButtonClass('inventory', tab === t)}>
              {t === 'new' ? 'New Adjustment' : 'History'}
            </button>
          ))}
        </div>
      </div>

      {tab === 'new' ? (
        <div className="px-5 py-4 max-w-4xl space-y-4">
          {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
          {success && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">{success}</div>}

          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Header</p>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Warehouse *</label>
                <select value={warehouseId} onChange={e => setWarehouseId(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— Select —</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Date</label>
                <input type="date" value={adjDate} onChange={e => setAdjDate(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Reason</label>
                <select value={reason} onChange={e => setReason(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  {REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
                </select>
              </div>
              <div className="col-span-3">
                <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                <input value={notes} onChange={e => setNotes(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Items</p>
              <select onChange={e => { addLine(e.target.value); e.target.value = '' }}
                className="ml-auto border border-gray-200 rounded px-2.5 py-1 text-xs w-64 focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">+ Add Item…</option>
                {items.map(i => <option key={i.id} value={i.id}>{i.item_code} — {i.description}</option>)}
              </select>
            </div>
            {lines.length === 0 ? (
              <div className="py-10 text-center text-xs text-gray-400">Add items using the dropdown above</div>
            ) : (
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Item','Method','Qty Before','Qty Adjusted (±)','Qty After','Lot / Serial','GL Offset Account',''].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {lines.map((l, idx) => (
                    <tr key={l.item_id} className="hover:bg-gray-50/60">
                      <td className="px-3 py-2">
                        <p className="font-semibold text-gray-900">{l.item_code}</p>
                        <p className="text-[10px] text-gray-400">{l.item_name}</p>
                      </td>
                      <td className="px-3 py-2 text-gray-500 text-[10px]">{l.costing_method === 'weighted_average' ? 'WAC' : l.costing_method === 'fifo' ? 'FIFO' : 'Specific ID'}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-500">{l.qty_before.toLocaleString()}</td>
                      <td className="px-3 py-2">
                        <input type="number" step="0.0001" value={l.qty_adjusted}
                          onChange={e => updateLine(idx, 'qty_adjusted', e.target.value)}
                          className="border border-gray-300 rounded px-2 py-1 text-xs font-mono text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                      </td>
                      <td className={`px-3 py-2 text-right font-mono font-semibold ${l.qty_before + Number(l.qty_adjusted) < 0 ? 'text-red-600' : 'text-gray-900'}`}>
                        {(l.qty_before + Number(l.qty_adjusted)).toLocaleString('en-PH', { maximumFractionDigits: 4 })} {l.uom_code}
                      </td>
                      <td className="px-3 py-2">
                        {l.costing_method !== 'weighted_average' ? (
                          <div className="flex gap-1">
                            <input value={l.lot_number} onChange={e => updateLine(idx, 'lot_number', e.target.value)}
                              placeholder="Lot" className="border border-gray-200 rounded px-1.5 py-0.5 text-xs w-16 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                            <input value={l.serial_number} onChange={e => updateLine(idx, 'serial_number', e.target.value)}
                              placeholder="Serial" className="border border-gray-200 rounded px-1.5 py-0.5 text-xs w-20 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                          </div>
                        ) : <span className="text-gray-300">—</span>}
                      </td>
                      <td className="px-3 py-2">
                        <select value={l.gl_offset_account_id} onChange={e => updateLine(idx, 'gl_offset_account_id', e.target.value)}
                          className="border border-gray-200 rounded px-1.5 py-1 text-[10px] w-48 focus:outline-none focus:ring-1 focus:ring-gray-900">
                          <option value="">— Skip GL —</option>
                          {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                        </select>
                      </td>
                      <td className="px-3 py-2">
                        <button onClick={() => removeLine(idx)} className="text-red-400 hover:text-red-600 text-xs">✕</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          {pendingId && (
            <GLImpactPanel companyId={companyId} sourceDocType="INV_ADJ" sourceDocId={pendingId} previewRows={[]} />
          )}

          <div className="flex gap-2">
            {!pendingId ? (
              <button onClick={saveDraft} disabled={saving || lines.length === 0 || !warehouseId}
                className="px-4 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
                {saving ? 'Saving…' : 'Save Draft'}
              </button>
            ) : (
              <button onClick={post} disabled={posting}
                className="px-4 py-1.5 bg-green-700 text-white rounded text-sm font-medium hover:bg-green-800 disabled:opacity-40">
                {posting ? 'Posting…' : 'Post Adjustment'}
              </button>
            )}
          </div>
        </div>
      ) : (
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Number','Date','Warehouse','Reason','Notes','Status'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.length === 0 ? (
                  <tr><td colSpan={6} className="py-12 text-center text-gray-400">No adjustments</td></tr>
                ) : history.map(a => (
                  <tr key={a.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{a.adjustment_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{a.adjustment_date}</td>
                    <td className="px-3 py-2 text-gray-800">{a.warehouse_name}</td>
                    <td className="px-3 py-2 text-gray-600">{REASONS.find(r => r.value === a.reason)?.label || a.reason}</td>
                    <td className="px-3 py-2 text-gray-500 max-w-[200px] truncate">{a.notes || '—'}</td>
                    <td className="px-3 py-2">
                      <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${a.status === 'posted' ? 'bg-green-50 text-green-700' : 'bg-yellow-50 text-yellow-700'}`}>
                        {a.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
