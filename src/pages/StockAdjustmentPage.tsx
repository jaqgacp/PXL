import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { AuditTrailSection } from '@/components/ui/shared'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { useBranchLabel } from '@/hooks/useBranchLabel'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'
import { transactionSegmentButtonClass } from '@/lib/transactionWorkspace'

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
  const [viewAdjustment, setViewAdjustment] = useState<Adjustment | null>(null)
  const [viewLines, setViewLines] = useState<AdjLine[]>([])
  const branchLabel = useBranchLabel(branchId)

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

  const openAdjustment = async (adjustment: Adjustment) => {
    setViewAdjustment(adjustment)
    const { data } = await supabase.from('stock_adjustment_lines')
      .select('item_id,qty_before,qty_adjusted,lot_number,serial_number,gl_offset_account_id,items(item_code,description,costing_method,units_of_measure(uom_code))')
      .eq('adjustment_id', adjustment.id)
    setViewLines(((data || []) as any[]).map(line => ({
      item_id: line.item_id,
      item_code: line.items?.item_code || '',
      item_name: line.items?.description || '',
      uom_code: line.items?.units_of_measure?.uom_code || '',
      costing_method: line.items?.costing_method || 'weighted_average',
      qty_before: Number(line.qty_before || 0),
      qty_adjusted: String(line.qty_adjusted || 0),
      lot_number: line.lot_number || '',
      serial_number: line.serial_number || '',
      gl_offset_account_id: line.gl_offset_account_id || '',
    })))
  }

  if (tab === 'history' && !viewAdjustment) {
    return (
      <div>
        <div className="pxl-transaction-header flex items-center gap-3 rounded-lg px-4 py-3">
          <span className="text-xs font-semibold uppercase tracking-wide">Inventory Adjustments</span>
          <div className="ml-auto flex gap-1">
            {(['new', 'history'] as const).map(current => <button key={current} onClick={() => setTab(current)} className={transactionSegmentButtonClass('inventory', tab === current)}>{current === 'new' ? 'New Adjustment' : 'History'}</button>)}
          </div>
        </div>
        <div className="mt-3 overflow-hidden rounded-lg border border-gray-200 bg-white">
          <table className="pxl-data-grid w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Number','Date','Warehouse','Reason','Notes','Status'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.length === 0 ? (
                  <tr><td colSpan={6} className="py-12 text-center text-gray-400">No adjustments</td></tr>
                ) : history.map(a => (
                  <tr key={a.id} className="cursor-pointer hover:bg-gray-50/60" onClick={() => void openAdjustment(a)}>
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
    )
  }

  const readOnly = !!viewAdjustment
  const activeLines = viewAdjustment ? viewLines : lines
  const activeStatus = viewAdjustment?.status || (pendingId ? 'draft' : 'draft')
  const activeDate = viewAdjustment?.adjustment_date || adjDate
  const activeReason = viewAdjustment?.reason || reason
  const activeNotes = viewAdjustment?.notes || notes
  const selectedWarehouse = warehouses.find(warehouse => warehouse.id === warehouseId)
  const activeWarehouseLabel = viewAdjustment?.warehouse_name || (selectedWarehouse ? `${selectedWarehouse.warehouse_code} — ${selectedWarehouse.warehouse_name}` : 'Not selected')
  const quantityAdjustment = activeLines.reduce((sum, line) => sum + Number(line.qty_adjusted || 0), 0)
  const validationErrors = [
    !viewAdjustment && !warehouseId ? 'Warehouse is required.' : '',
    activeLines.length === 0 ? 'At least one inventory line is required.' : '',
    activeLines.some(line => line.qty_before + Number(line.qty_adjusted) < 0) ? 'An adjustment would produce negative on-hand quantity.' : '',
    activeLines.some(line => Number(line.qty_adjusted) !== 0 && !line.gl_offset_account_id) ? 'GL offset account is required for adjusted lines before posting.' : '',
  ].filter(Boolean)
  const activeId = viewAdjustment?.id || pendingId
  const workflowSteps = [{ key: 'draft', label: 'Draft' }, { key: 'posted', label: 'Posted' }]

  return (
    <TransactionWorkspace
      title="Inventory Adjustment"
      documentNo={viewAdjustment?.adjustment_number || (pendingId ? 'Saved Draft' : null)}
      status={activeStatus}
      family="inventory"
      identity={{ name: activeWarehouseLabel, secondary: REASONS.find(item => item.value === activeReason)?.label || activeReason }}
      metrics={[
        { label: 'Quantity Change', value: quantityAdjustment.toLocaleString('en-PH', { maximumFractionDigits: 4 }), emphasis: true },
        { label: 'Item Count', value: activeLines.length },
        { label: 'Valuation', value: activeId ? 'From posting engine' : 'Pending save' },
      ]}
      meta={[{ label: 'Inventory', value: activeStatus === 'posted' ? 'Movement posted' : 'Not posted', tone: activeStatus === 'posted' ? 'success' : 'neutral' }]}
      actions={[
        ...(!readOnly && !pendingId ? [{ key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: saveDraft, disabled: saving || lines.length === 0 || !warehouseId, variant: 'primary' as const }] : []),
        ...(!readOnly && pendingId ? [{ key: 'post', label: posting ? 'Posting…' : 'Post Adjustment', onClick: post, disabled: posting, variant: 'primary' as const }] : []),
        { key: 'history', label: 'History', onClick: () => { setViewAdjustment(null); setTab('history') }, group: 'more' as const },
      ]}
      workflow={{ steps: workflowSteps, currentKey: activeStatus }}
      cards={[
        { title: 'Document Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className="pxl-field-label">Adjustment Date<input type="date" value={activeDate} disabled={readOnly} onChange={event => setAdjDate(event.target.value)} className="mt-1 w-full rounded border border-gray-300 px-2.5 py-2 text-sm" /></label><label className="pxl-field-label">Reason<select value={activeReason} disabled={readOnly} onChange={event => setReason(event.target.value)} className="mt-1 w-full rounded border border-gray-300 px-2.5 py-2 text-xs">{REASONS.map(item => <option key={item.value} value={item.value}>{item.label}</option>)}</select></label><div><div className="pxl-field-label">Branch</div><div className="pxl-body-text mt-1">{branchLabel}</div></div><div><div className="pxl-field-label">Posting Status</div><div className="pxl-body-text mt-1">{activeStatus}</div></div></div> },
        { title: 'Warehouse Context', content: readOnly ? <dl className="grid gap-3 sm:grid-cols-2"><div><dt className="pxl-field-label">Warehouse</dt><dd className="pxl-body-text mt-1">{activeWarehouseLabel}</dd></div><div><dt className="pxl-field-label">Movement</dt><dd className="pxl-body-text mt-1">On-hand adjustment</dd></div></dl> : <div className="grid gap-3"><label className="pxl-field-label">Warehouse *<select value={warehouseId} onChange={event => setWarehouseId(event.target.value)} className="mt-1 w-full rounded border border-gray-300 px-2.5 py-2 text-xs"><option value="">— Select —</option>{warehouses.map(warehouse => <option key={warehouse.id} value={warehouse.id}>{warehouse.warehouse_code} — {warehouse.warehouse_name}</option>)}</select></label><div className="grid gap-3 sm:grid-cols-2"><div><div className="pxl-field-label">Warehouse Role</div><div className="pxl-body-text mt-1">Source and destination of variance</div></div><div><div className="pxl-field-label">Valuation</div><div className="pxl-body-text mt-1">Posting engine</div></div></div></div> },
        { title: 'Movement Context', content: <div className="grid gap-3 sm:grid-cols-2"><div><div className="pxl-field-label">Items</div><div className="pxl-body-text mt-1">{activeLines.length}</div></div><div><div className="pxl-field-label">Quantity Change</div><div className="pxl-body-text mt-1 font-mono">{quantityAdjustment.toLocaleString('en-PH', { maximumFractionDigits: 4 })}</div></div><div><div className="pxl-field-label">Lot / Serial Lines</div><div className="pxl-body-text mt-1">{activeLines.filter(line => line.lot_number || line.serial_number).length}</div></div><div><div className="pxl-field-label">Offset Accounts</div><div className="pxl-body-text mt-1">{activeLines.filter(line => line.gl_offset_account_id).length} mapped</div></div></div> },
      ]}
      tabBadges={{ lines: activeLines.length }}
      tabContent={{
        lines: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
          {!readOnly && <div className="flex items-center gap-2 border-b border-[var(--pxl-border-medium)] px-3 py-2"><h2 className="pxl-section-title">Inventory Movement Lines</h2><select onChange={event => { addLine(event.target.value); event.target.value = '' }} className="ml-auto w-64 rounded border border-gray-300 px-2.5 py-1 text-xs"><option value="">+ Add Item…</option>{items.map(item => <option key={item.id} value={item.id}>{item.item_code} — {item.description}</option>)}</select></div>}
          {activeLines.length === 0 ? <TransactionEmptyState>Add inventory items to begin the adjustment.</TransactionEmptyState> : <table className="pxl-data-grid w-full text-xs"><thead><tr>{['Item', 'Method', 'Qty Before', 'Qty Adjusted (±)', 'Qty After', 'Lot / Serial', 'GL Offset Account', ''].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody>{activeLines.map((line, index) => <tr key={line.item_id}><td><p className="font-semibold">{line.item_code}</p><p className="pxl-caption">{line.item_name}</p></td><td>{line.costing_method === 'weighted_average' ? 'WAC' : line.costing_method === 'fifo' ? 'FIFO' : 'Specific ID'}</td><td className="text-right font-mono">{line.qty_before.toLocaleString()}</td><td className="text-right">{readOnly ? <span className="font-mono">{Number(line.qty_adjusted).toLocaleString()}</span> : <input type="number" step="0.0001" value={line.qty_adjusted} onChange={event => updateLine(index, 'qty_adjusted', event.target.value)} className="w-24 rounded border border-gray-300 px-2 py-1 text-right font-mono" />}</td><td className={`text-right font-mono font-semibold ${line.qty_before + Number(line.qty_adjusted) < 0 ? 'text-red-700' : ''}`}>{(line.qty_before + Number(line.qty_adjusted)).toLocaleString('en-PH', { maximumFractionDigits: 4 })} {line.uom_code}</td><td>{readOnly ? `${line.lot_number || '—'} / ${line.serial_number || '—'}` : line.costing_method !== 'weighted_average' ? <div className="flex gap-1"><input value={line.lot_number} onChange={event => updateLine(index, 'lot_number', event.target.value)} placeholder="Lot" className="w-16 rounded border px-1.5 py-0.5" /><input value={line.serial_number} onChange={event => updateLine(index, 'serial_number', event.target.value)} placeholder="Serial" className="w-20 rounded border px-1.5 py-0.5" /></div> : '—'}</td><td>{readOnly ? (coa.find(account => account.id === line.gl_offset_account_id) ? `${coa.find(account => account.id === line.gl_offset_account_id)?.account_code} — ${coa.find(account => account.id === line.gl_offset_account_id)?.account_name}` : '—') : <select value={line.gl_offset_account_id} onChange={event => updateLine(index, 'gl_offset_account_id', event.target.value)} className="w-48 rounded border px-1.5 py-1"><option value="">— Select offset —</option>{coa.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select>}</td><td>{!readOnly && <button onClick={() => removeLine(index)} className="text-red-600" aria-label={`Remove ${line.item_code}`}>✕</button>}</td></tr>)}</tbody></table>}
        </div>,
        financial: <div className="ml-auto grid max-w-lg grid-cols-2 gap-2"><span className="text-gray-600">Total Quantity Change</span><span className="text-right font-mono">{quantityAdjustment.toLocaleString('en-PH', { maximumFractionDigits: 4 })}</span><span className="text-gray-600">Inventory Increase Lines</span><span className="text-right font-mono">{activeLines.filter(line => Number(line.qty_adjusted) > 0).length}</span><span className="text-gray-600">Inventory Decrease Lines</span><span className="text-right font-mono">{activeLines.filter(line => Number(line.qty_adjusted) < 0).length}</span><span className="pxl-section-title border-t pt-2">Valuation Impact</span><span className="border-t pt-2 text-right text-xs">{activeId ? 'Posting engine / GL tab' : 'Available after save'}</span></div>,
        gl: activeId ? <GLImpactPanel companyId={companyId} sourceDocType="INV_ADJ" sourceDocId={activeId} previewRows={[]} /> : <TransactionEmptyState>Save the draft to request an authoritative inventory GL preview.</TransactionEmptyState>,
        tax: <TransactionEmptyState>Inventory Adjustments do not create a tax impact in the current posting design.</TransactionEmptyState>,
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">{success}</div>}{validationErrors.length > 0 ? validationErrors.map(message => <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Inventory movement and GL mappings are ready.</div>}</div>,
        workflow: <ol className="grid gap-2 sm:grid-cols-2">{workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === activeStatus ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
        approval: <TransactionEmptyState>No separate approval record is exposed for Inventory Adjustments; posting remains permission and period controlled.</TransactionEmptyState>,
        audit: activeId ? <AuditTrailSection tableName="stock_adjustments" recordId={activeId} /> : <TransactionEmptyState>Audit history begins after the adjustment is saved.</TransactionEmptyState>,
        related: <TransactionEmptyState>No source or destination document is linked to this standalone Inventory Adjustment.</TransactionEmptyState>,
        party: <dl className="grid gap-3 sm:grid-cols-2"><div><dt className="pxl-field-label">Warehouse</dt><dd className="pxl-body-text mt-1">{activeWarehouseLabel}</dd></div><div><dt className="pxl-field-label">Branch</dt><dd className="pxl-body-text mt-1">{branchLabel}</dd></div></dl>,
        notes: <label className="pxl-field-label">Adjustment Notes<textarea value={activeNotes} disabled={readOnly} onChange={event => setNotes(event.target.value)} rows={5} className="mt-1 w-full rounded border border-gray-300 px-2.5 py-2 text-sm" /></label>,
        activity: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Saved Draft</div><div className="pxl-body-text mt-1">{activeId ? 'Yes' : 'No'}</div></div><div><div className="pxl-field-label">Posted</div><div className="pxl-body-text mt-1">{activeStatus === 'posted' ? 'Yes' : 'No'}</div></div><div><div className="pxl-field-label">Movement Status</div><div className="pxl-body-text mt-1">{activeStatus}</div></div></div>,
        system: <SystemMetadataPanel facts={[
          { label: 'Internal ID', value: activeId || 'Assigned when saved', hint: 'Transaction identity' },
          { label: 'Document Number', value: viewAdjustment?.adjustment_number || 'Generated from number series', hint: 'Inventory Adjustment number' },
          { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
          { label: 'Branch ID', value: branchId || '—', hint: 'Posting context' },
          { label: 'Warehouse', value: activeWarehouseLabel, hint: 'Inventory context' },
          { label: 'Posting Status', value: activeStatus, hint: 'Lifecycle metadata' },
        ]} />,
      }}
      emptyTabMessages={{ attachments: 'No attachments have been added to this Inventory Adjustment.' }}
      sidebarPanels={[
        { key: 'inventory', title: 'Inventory', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Quantity Change</span><span className="font-mono text-sm font-bold">{quantityAdjustment.toLocaleString('en-PH', { maximumFractionDigits: 4 })}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Items</span><span className="font-mono text-xs">{activeLines.length}</span></div></div> },
        { key: 'gl', title: 'GL', content: <p className="pxl-caption">{activeId ? 'Authoritative impact is available in the GL Impact tab.' : 'Save the draft to preview posting impact.'}</p> },
        { key: 'warehouse', title: 'Warehouse', content: <p className="text-xs font-semibold">{activeWarehouseLabel}</p> },
        { key: 'status', title: 'Movement Status', content: <p className="pxl-body-text">{activeStatus}</p> },
      ]}
      footer={<span>{viewAdjustment ? `${viewAdjustment.adjustment_number} · ${viewAdjustment.status}` : pendingId ? 'Saved draft ready for posting' : 'Unsaved Inventory Adjustment'}</span>}
      onBack={() => { setViewAdjustment(null); setTab('history') }}
      backLabel="Inventory Adjustments"
    />
  )
}
