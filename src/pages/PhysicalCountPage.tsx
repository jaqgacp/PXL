import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { TablesInsert } from '@/lib/database.types'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type Warehouse = { id: string; warehouse_code: string; warehouse_name: string }
type COA = { id: string; account_code: string; account_name: string }
type CountLine = {
  id?: string; item_id: string; item_code: string; item_name: string; uom_code: string
  lot_number: string | null; serial_number: string | null
  system_qty: number; counted_qty: string; unit_cost: number; gl_variance_account_id: string
}
type Sheet = { id: string; count_number: string; count_date: string; warehouse_name: string; status: string }

export default function PhysicalCountPage() {
  const { companyId, branchId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [history, setHistory] = useState<Sheet[]>([])
  const [warehouseId, setWarehouseId] = useState('')
  const [countDate, setCountDate] = useState(today)
  const [notes, setNotes] = useState('')
  const [lines, setLines] = useState<CountLine[]>([])
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [posting, setPosting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: whs }, { data: coaData }, { data: sheetData }] = await Promise.all([
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
      supabase.from('physical_count_sheets').select(`id,count_number,count_date,status,warehouses!inner(warehouse_name)`).eq('company_id', companyId).order('count_date', { ascending: false }).limit(50),
    ])
    setWarehouses((whs as Warehouse[]) || [])
    setCoa((coaData as COA[]) || [])
    setHistory(((sheetData || []) as any[]).map(s => ({ id: s.id, count_number: s.count_number, count_date: s.count_date, status: s.status, warehouse_name: s.warehouses?.warehouse_name ?? '' })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  // Load current stock balances when warehouse is selected
  const loadBalances = async (whId: string) => {
    if (!whId) { setLines([]); return }
    const { data } = await supabase.from('stock_balances').select(`
      item_id, qty_on_hand, wac_unit_cost,
      items!inner(item_code, description, units_of_measure!inner(uom_code))
    `).eq('warehouse_id', whId).gt('qty_on_hand', 0)

    setLines(((data || []) as any[]).map(r => ({
      item_id: r.item_id,
      item_code: r.items?.item_code ?? '',
      item_name: r.items?.description ?? '',
      uom_code: r.items?.units_of_measure?.uom_code ?? '',
      lot_number: null, serial_number: null,
      system_qty: Number(r.qty_on_hand),
      counted_qty: Number(r.qty_on_hand).toString(),
      unit_cost: Number(r.wac_unit_cost),
      gl_variance_account_id: '',
    })))
  }

  const onWhChange = (whId: string) => {
    setWarehouseId(whId)
    setPendingId(null)
    loadBalances(whId)
  }

  const saveDraft = async () => {
    if (!companyId || !warehouseId) { setError('Select a warehouse'); return }
    setSaving(true); setError(''); setSuccess('')

    const { data: csData, error: e1 } = await supabase.from('physical_count_sheets').insert({
      company_id: companyId, branch_id: branchId || null, warehouse_id: warehouseId,
      count_number: 'PENDING', count_date: countDate,
      notes: notes || null, status: 'counting',
    }).select().single()
    if (e1 || !csData) { setSaving(false); setError(e1?.message || 'Failed'); return }

    const { error: e2 } = await supabase.from('physical_count_sheet_lines').insert(
      lines.map(l => ({
        count_sheet_id: (csData as any).id, company_id: companyId, item_id: l.item_id,
        system_qty: l.system_qty,
        counted_qty: l.counted_qty !== '' ? Number(l.counted_qty) : null,
        unit_cost: l.unit_cost,
        lot_number: l.lot_number, serial_number: l.serial_number,
        gl_variance_account_id: l.gl_variance_account_id || null,
      }))
    )
    setSaving(false)
    if (e2) { setError(e2.message); return }
    setPendingId((csData as any).id)
    setSuccess(`Count sheet saved as ${(csData as any).count_number}. Review variances, then post.`)
  }

  const post = async () => {
    if (!pendingId) return
    // Update lines first
    const { error: updErr } = await supabase.from('physical_count_sheet_lines')
      .upsert(lines.filter(l => l.id).map(l => ({
        id: l.id, counted_qty: l.counted_qty !== '' ? Number(l.counted_qty) : null,
        gl_variance_account_id: l.gl_variance_account_id || null,
      })) as unknown as TablesInsert<'physical_count_sheet_lines'>[])
    if (updErr) { setError(updErr.message); return }

    setPosting(true); setError(''); setSuccess('')
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'INV_COUNT', p_source_doc_id: pendingId })
    if (previewError) {
      setPosting(false)
      setError(`Physical Count is not ready to post: ${previewError.message}`)
      return
    }
    const { error: e } = await supabase.rpc('fn_post_physical_count', { p_sheet_id: pendingId })
    setPosting(false)
    if (e) { setError(e.message); return }
    setSuccess('Physical count posted. Variances applied to stock and GL.')
    setPendingId(null); setLines([]); setWarehouseId(''); setNotes('')
    load()
  }

  const variances = lines.filter(l => l.counted_qty !== '' && Number(l.counted_qty) !== l.system_qty)

  return (
    <LegacyTransactionWorkspace title="Physical Count" family="inventory" pattern="B" posting
      status={pendingId ? 'draft' : 'draft'} identity={warehouses.find(w => w.id === warehouseId)?.warehouse_name}
      financialFacts={[{ label: 'Counted Items', value: lines.length }, { label: 'Variance Lines', value: variances.length }, { label: 'Quantity Variance', value: lines.reduce((sum, line) => sum + (line.counted_qty === '' ? 0 : Number(line.counted_qty) - line.system_qty), 0), hint: 'Counted quantity less system quantity' }, { label: 'Value Variance', value: lines.reduce((sum, line) => sum + (line.counted_qty === '' ? 0 : (Number(line.counted_qty) - line.system_qty) * line.unit_cost), 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }]}
      contextFacts={[{ label: 'Warehouse', value: warehouses.find(w => w.id === warehouseId)?.warehouse_name || 'Not selected' }, { label: 'Count Date', value: countDate }, { label: 'Movement State', value: pendingId ? 'Saved count awaiting posting' : 'Unsaved count' }]}
      sourceDocType="INV_COUNT" sourceDocId={pendingId} auditTable="inventory_counts"
      actions={[
        { key: 'save', label: saving ? 'Saving…' : 'Save Count Sheet', onClick: saveDraft, disabled: saving || !warehouseId || lines.length === 0, hidden: !!pendingId },
        { key: 'post', label: posting ? 'Posting…' : `Post Variances (${variances.length})`, onClick: post, disabled: posting, hidden: !pendingId, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Count Date', card: 0, content: <input type="date" value={countDate} onChange={e => setCountDate(e.target.value)} disabled={!!pendingId} className="pxl-input w-full" /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{pendingId ? 'Saved count sheet' : 'Generated on save'}</div> },
        { key: 'warehouse', label: 'Warehouse *', card: 1, span: 2, content: <select value={warehouseId} onChange={e => onWhChange(e.target.value)} disabled={!!pendingId} className="pxl-input w-full"><option value="">— Select —</option>{warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}</select> },
        { key: 'notes', label: 'Notes', card: 2, span: 2, content: <input value={notes} onChange={e => setNotes(e.target.value)} disabled={!!pendingId} className="pxl-input w-full" /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-700">{success}</div>}{variances.length > 0 && <div className="pxl-validation-message border border-amber-200 bg-amber-50 text-amber-800">{variances.length} variances detected; review before posting.</div>}</div>,
        gl: pendingId ? <GLImpactPanel companyId={companyId} sourceDocType="INV_COUNT" sourceDocId={pendingId} previewRows={[]} /> : undefined,
        activity: <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Count #','Date','Warehouse','Status'].map(h => <th key={h} className="text-left">{h}</th>)}</tr></thead><tbody>{history.length === 0 ? <tr><td colSpan={4} className="pxl-empty-state">No count sheets</td></tr> : history.map(s => <tr key={s.id}><td className="font-mono font-semibold">{s.count_number}</td><td>{s.count_date}</td><td>{s.warehouse_name}</td><td className="capitalize">{s.status}</td></tr>)}</tbody></table></div>,
      }}>
    <div>
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Count Sheet — {lines.length} items</p>
            </div>
            {lines.length === 0 ? (
              <div className="py-12 text-center text-xs text-gray-400">Select a warehouse to load items</div>
            ) : (
              <div className="overflow-x-auto max-h-[60vh]">
                <table className="pxl-data-grid w-full">
                  <thead className="bg-gray-50 border-b border-gray-200 sticky top-0">
                    <tr>{['Item Code','Item Name','System Qty','Counted Qty','Variance','Unit Cost (₱)','Variance Value (₱)','Variance GL Account'].map(h => (
                      <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                    ))}</tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {lines.map((l, idx) => {
                      const counted = l.counted_qty !== '' ? Number(l.counted_qty) : l.system_qty
                      const variance = counted - l.system_qty
                      const varianceValue = variance * l.unit_cost
                      return (
                        <tr key={l.item_id} className={`hover:bg-gray-50/60 ${variance !== 0 ? 'bg-amber-50/40' : ''}`}>
                          <td className="px-3 py-1.5 font-mono font-semibold text-gray-900">{l.item_code}</td>
                          <td className="px-3 py-1.5 text-gray-800 max-w-[160px] truncate">{l.item_name}</td>
                          <td className="px-3 py-1.5 text-right font-mono text-gray-600">{l.system_qty.toLocaleString('en-PH', { maximumFractionDigits: 4 })} {l.uom_code}</td>
                          <td className="px-3 py-1.5">
                            <input type="number" min={0} step={0.0001} value={l.counted_qty}
                              onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, counted_qty: e.target.value } : x))}
                              className="border border-gray-300 rounded px-2 py-0.5 text-xs font-mono text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                          </td>
                          <td className={`px-3 py-1.5 text-right font-mono font-semibold ${variance > 0 ? 'text-green-700' : variance < 0 ? 'text-red-700' : 'text-gray-400'}`}>
                            {variance !== 0 ? (variance > 0 ? '+' : '') + variance.toLocaleString('en-PH', { maximumFractionDigits: 4 }) : '—'}
                          </td>
                          <td className="px-3 py-1.5 text-right font-mono text-gray-600">{l.unit_cost.toLocaleString('en-PH', { minimumFractionDigits: 4 })}</td>
                          <td className={`px-3 py-1.5 text-right font-mono font-semibold ${varianceValue > 0 ? 'text-green-700' : varianceValue < 0 ? 'text-red-700' : 'text-gray-300'}`}>
                            {variance !== 0 ? (varianceValue > 0 ? '' : '') + varianceValue.toLocaleString('en-PH', { minimumFractionDigits: 2 }) : '—'}
                          </td>
                          <td className="px-3 py-1.5">
                            {variance !== 0 ? (
                              <select value={l.gl_variance_account_id}
                                onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, gl_variance_account_id: e.target.value } : x))}
                                className="border border-gray-200 rounded px-1.5 py-0.5 text-[10px] w-48 focus:outline-none focus:ring-1 focus:ring-gray-900">
                                <option value="">— Use warehouse default —</option>
                                {coa.map(a => <option key={a.id} value={a.id}>{a.account_code}</option>)}
                              </select>
                            ) : <span className="text-gray-300">—</span>}
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
    </LegacyTransactionWorkspace>
  )
}
