import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type Warehouse = { id: string; warehouse_code: string; warehouse_name: string }
type Item = { id: string; item_code: string; description: string; costing_method: string; uom_code: string }
type TxLine = { item_id: string; item_code: string; item_name: string; uom_code: string; costing_method: string; qty: string; lot_number: string; serial_number: string }
type TransferRecord = { id: string; transfer_number: string; transfer_date: string; from_wh: string; to_wh: string; status: string }

export default function StockTransferPage() {
  const { companyId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [items, setItems] = useState<Item[]>([])
  const [history, setHistory] = useState<TransferRecord[]>([])
  const [fromWh, setFromWh] = useState('')
  const [toWh, setToWh] = useState('')
  const [txDate, setTxDate] = useState(today)
  const [notes, setNotes] = useState('')
  const [lines, setLines] = useState<TxLine[]>([])
  const [saving, setSaving] = useState(false)
  const [posting, setPosting] = useState(false)
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: whs }, { data: itemData }, { data: txData }] = await Promise.all([
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('items').select('id,item_code,description,costing_method,units_of_measure!inner(uom_code)').eq('company_id', companyId).eq('is_active', true).eq('item_type', 'inventory_item').order('item_code'),
      supabase.from('stock_transfers').select(`
        id,transfer_number,transfer_date,status,
        from_wh:warehouses!stock_transfers_from_warehouse_id_fkey(warehouse_name),
        to_wh:warehouses!stock_transfers_to_warehouse_id_fkey(warehouse_name)
      `).eq('company_id', companyId).order('transfer_date', { ascending: false }).limit(50),
    ])
    setWarehouses((whs as Warehouse[]) || [])
    setItems(((itemData || []) as any[]).map(i => ({ id: i.id, item_code: i.item_code, description: i.description, costing_method: i.costing_method || 'weighted_average', uom_code: i.units_of_measure?.uom_code || '' })))
    setHistory(((txData || []) as any[]).map(t => ({ id: t.id, transfer_number: t.transfer_number, transfer_date: t.transfer_date, status: t.status, from_wh: t.from_wh?.warehouse_name ?? '', to_wh: t.to_wh?.warehouse_name ?? '' })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  const addLine = (itemId: string) => {
    const item = items.find(i => i.id === itemId)
    if (!item || lines.find(l => l.item_id === itemId)) return
    setLines(p => [...p, { item_id: itemId, item_code: item.item_code, item_name: item.description, uom_code: item.uom_code, costing_method: item.costing_method, qty: '', lot_number: '', serial_number: '' }])
  }

  const saveDraft = async () => {
    if (!companyId || !fromWh || !toWh) { setError('Select both warehouses'); return }
    if (fromWh === toWh) { setError('Source and destination must differ'); return }
    if (lines.length === 0 || lines.some(l => !l.qty || Number(l.qty) <= 0)) { setError('All lines need a positive quantity'); return }
    setSaving(true); setError(''); setSuccess('')

    const { data: txData, error: e1 } = await supabase.from('stock_transfers').insert({
      company_id: companyId, transfer_number: 'PENDING',
      transfer_date: txDate, from_warehouse_id: fromWh, to_warehouse_id: toWh,
      status: 'draft', notes: notes || null,
    }).select().single()
    if (e1 || !txData) { setSaving(false); setError(e1?.message || 'Failed'); return }

    const { error: e2 } = await supabase.from('stock_transfer_lines').insert(
      lines.map(l => ({
        transfer_id: (txData as any).id, company_id: companyId,
        item_id: l.item_id, qty_transferred: Number(l.qty),
        lot_number: l.lot_number || null, serial_number: l.serial_number || null,
      }))
    )
    setSaving(false)
    if (e2) { setError(e2.message); return }
    setPendingId((txData as any).id)
    setSuccess(`Draft saved. Ready to post.`)
  }

  const post = async () => {
    if (!pendingId) return
    setPosting(true); setError(''); setSuccess('')
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'INV_STX', p_source_doc_id: pendingId })
    if (previewError) {
      setPosting(false)
      setError(`Stock Transfer is not ready to post: ${previewError.message}`)
      return
    }
    const { error: e } = await supabase.rpc('fn_post_stock_transfer', { p_transfer_id: pendingId })
    setPosting(false)
    if (e) { setError(e.message); return }
    setSuccess('Transfer posted. Stock balances updated.')
    setPendingId(null); setLines([]); setNotes(''); setFromWh(''); setToWh('')
    load()
  }

  return (
    <LegacyTransactionWorkspace title="Stock Transfer" family="inventory" pattern="B" posting
      status={pendingId ? 'draft' : 'draft'} identity={warehouses.find(w => w.id === fromWh)?.warehouse_name}
      financialFacts={[{ label: 'Transfer Quantity', value: lines.reduce((sum, line) => sum + Number(line.qty || 0), 0), hint: 'Total quantity moving between warehouses' }, { label: 'Line Count', value: lines.length }]}
      contextFacts={[{ label: 'Source Warehouse', value: warehouses.find(w => w.id === fromWh)?.warehouse_name || 'Not selected' }, { label: 'Destination Warehouse', value: warehouses.find(w => w.id === toWh)?.warehouse_name || 'Not selected' }, { label: 'Transfer Date', value: txDate }]}
      sourceDocType="INV_STX" sourceDocId={pendingId} auditTable="stock_transfers"
      actions={[
        { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: saveDraft, disabled: saving, hidden: !!pendingId },
        { key: 'post', label: posting ? 'Posting…' : 'Post Transfer', onClick: post, disabled: posting, hidden: !pendingId, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Transfer Date', card: 0, content: <input type="date" value={txDate} onChange={e => setTxDate(e.target.value)} className="pxl-input w-full" /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{pendingId ? 'Draft saved' : 'Generated on save'}</div> },
        { key: 'from', label: 'From Warehouse *', card: 1, span: 2, content: <select value={fromWh} onChange={e => setFromWh(e.target.value)} className="pxl-input w-full"><option value="">— Select —</option>{warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}</select> },
        { key: 'to', label: 'To Warehouse *', card: 2, span: 2, content: <select value={toWh} onChange={e => setToWh(e.target.value)} className="pxl-input w-full"><option value="">— Select —</option>{warehouses.filter(w => w.id !== fromWh).map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}</select> },
        { key: 'notes', label: 'Notes', card: 2, span: 2, content: <input value={notes} onChange={e => setNotes(e.target.value)} className="pxl-input w-full" /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-700">{success}</div>}</div>,
        gl: pendingId ? <GLImpactPanel companyId={companyId} sourceDocType="INV_STX" sourceDocId={pendingId} previewRows={[]} /> : undefined,
        activity: <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Transfer #','Date','From','To','Status'].map(h => <th key={h} className="text-left">{h}</th>)}</tr></thead><tbody>{history.length === 0 ? <tr><td colSpan={5} className="pxl-empty-state">No transfers</td></tr> : history.map(t => <tr key={t.id}><td className="font-mono font-semibold">{t.transfer_number}</td><td>{t.transfer_date}</td><td>{t.from_wh}</td><td>{t.to_wh}</td><td className="capitalize">{t.status}</td></tr>)}</tbody></table></div>,
      }}>
    <div>
          <div className="overflow-hidden">
            <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Items to Transfer</p>
              <select onChange={e => { addLine(e.target.value); e.target.value = '' }}
                className="ml-auto border border-gray-200 rounded px-2.5 py-1 text-xs w-64 focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">+ Add Item…</option>
                {items.map(i => <option key={i.id} value={i.id}>{i.item_code} — {i.description}</option>)}
              </select>
            </div>
            {lines.length === 0 ? (
              <div className="py-10 text-center text-xs text-gray-400">Add items using the dropdown</div>
            ) : (
              <table className="pxl-data-grid w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Item','Method','Qty to Transfer','Lot / Serial',''].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {lines.map((l, idx) => (
                    <tr key={l.item_id}>
                      <td className="px-3 py-2">
                        <p className="font-semibold text-gray-900">{l.item_code}</p>
                        <p className="text-[10px] text-gray-400">{l.item_name}</p>
                      </td>
                      <td className="px-3 py-2 text-gray-500 text-[10px]">{l.costing_method === 'weighted_average' ? 'WAC' : l.costing_method === 'fifo' ? 'FIFO' : 'Specific ID'}</td>
                      <td className="px-3 py-2">
                        <div className="flex items-center gap-1">
                          <input type="number" min={0.0001} step={0.0001} value={l.qty}
                            onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, qty: e.target.value } : x))}
                            placeholder="0.0000"
                            className="border border-gray-300 rounded px-2 py-1 text-xs font-mono text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                          <span className="text-gray-400">{l.uom_code}</span>
                        </div>
                      </td>
                      <td className="px-3 py-2">
                        {l.costing_method !== 'weighted_average' ? (
                          <div className="flex gap-1">
                            <input value={l.lot_number}
                              onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, lot_number: e.target.value } : x))}
                              placeholder="Lot" className="border border-gray-200 rounded px-1.5 py-0.5 text-xs w-20 focus:outline-none" />
                            <input value={l.serial_number}
                              onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, serial_number: e.target.value } : x))}
                              placeholder="Serial" className="border border-gray-200 rounded px-1.5 py-0.5 text-xs w-24 focus:outline-none" />
                          </div>
                        ) : <span className="text-gray-300">—</span>}
                      </td>
                      <td className="px-3 py-2">
                        <button onClick={() => setLines(p => p.filter((_, i) => i !== idx))} className="text-red-400 hover:text-red-600 text-xs">✕</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

    </div>
    </LegacyTransactionWorkspace>
  )
}
