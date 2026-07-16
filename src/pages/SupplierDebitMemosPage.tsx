import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { transactionHeaderClass } from '@/lib/transactionWorkspace'
import { normalizePhTin } from '@/lib/philippines'

type SDMStatus = 'draft' | 'sent' | 'acknowledged' | 'cancelled'

type SDM = {
  id: string; company_id: string; sdm_number: string; dm_date: string
  supplier_id: string; supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  reason: string | null; total_amount: number; status: SDMStatus; created_at: string
}

type SDMLine = {
  _key: string; id?: string; item_id: string; description: string
  quantity: number; uom_id: string; unit_price: number; total_amount: number
}

type SupplierRef = { id: string; registered_name: string; tin: string }
type ItemRef = { id: string; item_code: string; description: string; uom_id: string; standard_cost: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const newLine = (): SDMLine => ({ _key: crypto.randomUUID(), item_id: '', description: '', quantity: 1, uom_id: '', unit_price: 0, total_amount: 0 })

export default function SupplierDebitMemosPage() {
  const { companyId, branchId } = useAppCtx()
  const [memos, setMemos] = useState<SDM[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editSDM, setEditSDM] = useState<Partial<SDM> | null>(null)
  const [lines, setLines] = useState<SDMLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'

  const loadMemos = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('supplier_debit_memos').select('*').eq('company_id', companyId).order('dm_date', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`sdm_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setMemos(data as SDM[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadMemos() }, [loadMemos, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('suppliers').select('id,registered_name,tin').eq('company_id', companyId).eq('is_active', true).order('registered_name').then(({ data }) => setSuppliers(data as SupplierRef[] || []))
    supabase.from('items').select('id,item_code,description,uom_id,standard_cost').eq('company_id', companyId).eq('is_active', true).order('description').then(({ data }) => setItems(data as ItemRef[] || []))
  }, [companyId])

  const updateLine = (idx: number, patch: Partial<SDMLine>) => {
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      const u = { ...l, ...patch }
      u.total_amount = Math.round(u.quantity * u.unit_price * 100) / 100
      return u
    }))
  }

  const grandTotal = lines.reduce((s, l) => s + l.total_amount, 0)

  const save = async () => {
    if (!companyId || !editSDM?.supplier_id) { setError('Supplier is required'); return }
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_supplier_debit_memo', {
        p_sdm_id: (editSDM.id || null)!,
        p_header: {
          company_id: companyId, branch_id: branchId || null,
          supplier_id: editSDM.supplier_id, supplier_name_snapshot: editSDM.supplier_name_snapshot,
          supplier_tin_snapshot: editSDM.supplier_tin_snapshot || '',
          dm_date: editSDM.dm_date, reason: editSDM.reason || '',
          reference_doc_id: null, reference_doc_type: null,
        },
        p_lines: lines.filter(l => l.description.trim()).map(l => ({
          item_id: l.item_id || null, description: l.description,
          quantity: l.quantity, uom_id: l.uom_id || null, unit_price: l.unit_price,
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadMemos()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const sendMemo = async (sdm: SDM) => {
    const { error: e } = await supabase.rpc('fn_send_supplier_debit_memo', { p_sdm_id: sdm.id })
    if (e) { alert(e.message); return }
    loadMemos()
  }

  const acknowledge = async (sdm: SDM) => {
    const { error: e } = await supabase.rpc('fn_acknowledge_supplier_debit_memo', { p_sdm_id: sdm.id })
    if (e) { alert(e.message); return }
    loadMemos()
  }

  const STATUS_COLORS: Record<string, string> = { draft: 'draft', sent: 'warning', acknowledged: 'posted', cancelled: 'error' }
  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'

  if (mode !== 'list') return (
    <div className="space-y-4" ref={listRef}>
      <div className={`${transactionHeaderClass('purchase')} justify-between`}>
        <div>
          <h2 className="text-base font-semibold text-gray-900">{editSDM?.id ? (readOnly ? 'Debit Memo to Supplier' : 'Edit Debit Memo') : 'New Debit Memo to Supplier'}</h2>
          {editSDM?.sdm_number && <p className="text-xs text-gray-500 mt-0.5">{editSDM.sdm_number} · <StatusBadge status={STATUS_COLORS[editSDM.status as string] || 'draft'} label={editSDM.status as string} /></p>}
        </div>
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-700">← Back</button>
      </div>
      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <div className="grid grid-cols-3 gap-3">
          <div><label className="block text-xs font-medium text-gray-700 mb-1">DM Date *</label><input type="date" value={editSDM?.dm_date || ''} disabled={readOnly} onChange={e => setEditSDM(p => ({ ...p, dm_date: e.target.value }))} className={inp} /></div>
          <div className="col-span-2"><label className="block text-xs font-medium text-gray-700 mb-1">Supplier *</label>
            <select value={editSDM?.supplier_id || ''} disabled={readOnly} onChange={e => { const s = suppliers.find(x => x.id === e.target.value); setEditSDM(p => ({ ...p, supplier_id: e.target.value, supplier_name_snapshot: s?.registered_name || '', supplier_tin_snapshot: s?.tin ? normalizePhTin(s.tin) : '' })) }} className={inp + ' w-full'}><option value="">— Select supplier —</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}</select>
          </div>
          <div className="col-span-3"><label className="block text-xs font-medium text-gray-700 mb-1">Reason for Debit Memo *</label><textarea value={editSDM?.reason || ''} disabled={readOnly} onChange={e => setEditSDM(p => ({ ...p, reason: e.target.value }))} rows={2} className={inp + ' w-full resize-none'} /></div>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Line Items</h3>
          {!readOnly && <button onClick={() => setLines(l => [...l, newLine()])} className="text-xs text-blue-600 hover:text-blue-800 font-medium">+ Add Line</button>}
        </div>
        <table className="w-full text-xs">
          <thead><tr className="border-b border-gray-200 text-gray-500">{['Item','Description','Qty','Unit Price','Total',!readOnly ? '' : undefined].filter(Boolean).map(h => <th key={h as string} className={`pb-2 font-medium text-left pr-2 ${h === 'Total' ? 'text-right' : ''}`}>{h}</th>)}</tr></thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={l._key} className="border-b border-gray-100">
                <td className="py-1.5 pr-1"><select value={l.item_id} disabled={readOnly} onChange={e => { const it = items.find(x => x.id === e.target.value); if (it) updateLine(i, { item_id: it.id, description: it.description, uom_id: it.uom_id, unit_price: it.standard_cost }); else updateLine(i, { item_id: e.target.value }) }} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-32 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{items.map(it => <option key={it.id} value={it.id}>{it.item_code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><input value={l.description} disabled={readOnly} onChange={e => updateLine(i, { description: e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-48 focus:outline-none focus:ring-1 focus:ring-gray-900" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.quantity} disabled={readOnly} onChange={e => updateLine(i, { quantity: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-20 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.unit_price} disabled={readOnly} onChange={e => updateLine(i, { unit_price: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-28 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 text-right font-mono font-medium">{fmt(l.total_amount)}</td>
                {!readOnly && <td className="py-1.5 pl-1"><button onClick={() => setLines(p => p.filter((_, j) => j !== i))} className="text-gray-300 hover:text-red-500 text-sm">×</button></td>}
              </tr>
            ))}
          </tbody>
          <tfoot><tr className="border-t-2 border-gray-300 font-semibold"><td colSpan={4} className="pt-2 text-right text-xs text-gray-600 pr-2">Total Amount</td><td className="pt-2 text-right font-mono text-sm">{fmt(grandTotal)}</td></tr></tfoot>
        </table>
      </div>
      {!readOnly && <div className="flex justify-end gap-2"><button onClick={() => setMode('list')} className="px-4 py-2 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button><button onClick={save} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : 'Save'}</button></div>}
    </div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Debit Memos to Suppliers</h2>
        <button onClick={() => { setEditSDM({ dm_date: today() }); setLines([newLine()]); setError(''); setMode('edit') }} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New Debit Memo</button>
      </div>
      <div className="flex gap-2">
        <input placeholder="Search…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option><option value="draft">Draft</option><option value="sent">Sent</option><option value="acknowledged">Acknowledged</option><option value="cancelled">Cancelled</option>
        </select>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : memos.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No debit memos found.</div> : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200"><tr>{['Date','DM Number','Supplier','Reason','Total Amount','Status',''].map(h => <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>)}</tr></thead>
            <tbody className="divide-y divide-gray-100">
              {memos.map(sdm => (
                <tr key={sdm.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={sdm.dm_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{sdm.sdm_number}</td>
                  <td className="px-3 py-2 text-gray-700">{sdm.supplier_name_snapshot}</td>
                  <td className="px-3 py-2 text-gray-500 max-w-xs truncate">{sdm.reason || '—'}</td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={sdm.total_amount} /></td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[sdm.status]} label={sdm.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => { setEditSDM({ ...sdm }); supabase.from('supplier_debit_memo_lines').select('*').eq('sdm_id', sdm.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id })) as SDMLine[] || [])); setMode('view') }} className="text-blue-600 hover:text-blue-800">View</button>
                      {sdm.status === 'draft' && <><button onClick={() => { setEditSDM({ ...sdm }); supabase.from('supplier_debit_memo_lines').select('*').eq('sdm_id', sdm.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id })) as SDMLine[] || [])); setError(''); setMode('edit') }} className="text-gray-600 hover:text-gray-800">Edit</button><button onClick={() => sendMemo(sdm)} className="text-orange-600 hover:text-orange-800">Send</button></>}
                      {sdm.status === 'sent' && <button onClick={() => acknowledge(sdm)} className="text-green-600 hover:text-green-800">Acknowledge</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
