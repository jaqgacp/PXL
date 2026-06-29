import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, DateCell } from '@/components/ui/shared'

type ReturnStatus = 'draft' | 'shipped' | 'completed' | 'cancelled'

type PReturn = {
  id: string; company_id: string; return_number: string; return_date: string
  rr_id: string; supplier_id: string; supplier_name_snapshot: string
  remarks: string | null; status: ReturnStatus; created_at: string
}

type ReturnLine = {
  _key: string; id?: string; rr_line_id: string; item_id: string
  description: string; max_qty: number; return_qty: number
  uom_id: string; unit_price: number; reason: string
}

type RRRef = { id: string; rr_number: string; supplier_name_snapshot: string; rr_date: string }

const today = () => new Date().toISOString().split('T')[0]
const fmt4 = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 4, maximumFractionDigits: 4 }).format(n)

export default function PurchaseReturnsPage() {
  const { companyId, branchId } = useAppCtx()
  const [returns, setReturns] = useState<PReturn[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editReturn, setEditReturn] = useState<Partial<PReturn> | null>(null)
  const [lines, setLines] = useState<ReturnLine[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [receivedRRs, setReceivedRRs] = useState<RRRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const readOnly = mode === 'view'

  const loadReturns = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('purchase_returns').select('*').eq('company_id', companyId).order('return_date', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    const { data } = await q
    setReturns(data as PReturn[] || [])
    setLoading(false)
  }, [companyId, fStatus])

  useEffect(() => { if (companyId) loadReturns() }, [loadReturns, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('receiving_reports').select('id,rr_number,supplier_name_snapshot,rr_date').eq('company_id', companyId).eq('status', 'received').order('rr_date', { ascending: false })
      .then(({ data }) => setReceivedRRs(data as RRRef[] || []))
  }, [companyId])

  const loadRRLines = async (rrId: string) => {
    const { data } = await supabase.from('receiving_report_lines').select('id,item_id,description,received_qty,uom_id,unit_price').eq('rr_id', rrId).order('line_number')
    return (data || []).map((l: any) => ({
      _key: l.id, rr_line_id: l.id, item_id: l.item_id || '',
      description: l.description, max_qty: l.received_qty, return_qty: 0,
      uom_id: l.uom_id || '', unit_price: l.unit_price || 0, reason: '',
    }))
  }

  const selectRR = async (rrId: string) => {
    const rr = receivedRRs.find(r => r.id === rrId)
    if (!rr) return
    setEditReturn(prev => ({ ...prev, rr_id: rr.id }))
    const lns = await loadRRLines(rr.id)
    setLines(lns)
  }

  const updateLine = (idx: number, patch: Partial<ReturnLine>) => {
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      const u = { ...l, ...patch }
      if (u.return_qty > u.max_qty) u.return_qty = u.max_qty
      return u
    }))
  }

  const save = async () => {
    if (!companyId || !editReturn?.rr_id) { setError('Receiving Report is required'); return }
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_purchase_return', {
        p_return_id: editReturn.id || null,
        p_header: {
          company_id: companyId, branch_id: branchId || null,
          rr_id: editReturn.rr_id, return_date: editReturn.return_date,
          remarks: editReturn.remarks || '',
        },
        p_lines: lines.filter(l => l.description.trim() && l.return_qty > 0).map(l => ({
          rr_line_id: l.rr_line_id || null, item_id: l.item_id || null,
          description: l.description, max_qty: l.max_qty, return_qty: l.return_qty,
          uom_id: l.uom_id || null, unit_price: l.unit_price, reason: l.reason || '',
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadReturns()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const ship = async (r: PReturn) => {
    const { error: e } = await supabase.rpc('fn_ship_purchase_return', { p_return_id: r.id })
    if (e) { alert(e.message); return }
    loadReturns()
  }

  const complete = async (r: PReturn) => {
    const { error: e } = await supabase.rpc('fn_complete_purchase_return', { p_return_id: r.id })
    if (e) { alert(e.message); return }
    loadReturns()
  }

  const STATUS_COLORS: Record<string, string> = { draft: 'draft', shipped: 'warning', completed: 'posted', cancelled: 'error' }
  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'

  if (mode !== 'list') return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-gray-900">{editReturn?.id ? (readOnly ? 'Purchase Return' : 'Edit Return') : 'New Purchase Return'}</h2>
          {editReturn?.return_number && <p className="text-xs text-gray-500 mt-0.5">{editReturn.return_number} · <StatusBadge status={STATUS_COLORS[editReturn.status as string] || 'draft'} label={editReturn.status as string} /></p>}
        </div>
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-700">← Back</button>
      </div>
      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <div className="grid grid-cols-3 gap-3">
          <div><label className="block text-xs font-medium text-gray-700 mb-1">Return Date *</label><input type="date" value={editReturn?.return_date || ''} disabled={readOnly} onChange={e => setEditReturn(p => ({ ...p, return_date: e.target.value }))} className={inp} /></div>
          <div className="col-span-2"><label className="block text-xs font-medium text-gray-700 mb-1">Reference Receiving Report *</label>
            <select value={editReturn?.rr_id || ''} disabled={readOnly || !!editReturn?.id} onChange={e => selectRR(e.target.value)} className={inp + ' w-full'}>
              <option value="">— Select received RR —</option>
              {receivedRRs.map(r => <option key={r.id} value={r.id}>{r.rr_number} — {r.supplier_name_snapshot} ({r.rr_date})</option>)}
            </select>
          </div>
          <div className="col-span-3"><label className="block text-xs font-medium text-gray-700 mb-1">Remarks</label><input type="text" value={editReturn?.remarks || ''} disabled={readOnly} onChange={e => setEditReturn(p => ({ ...p, remarks: e.target.value }))} className={inp + ' w-full'} /></div>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-3">Return Lines</h3>
        <table className="w-full text-xs">
          <thead><tr className="border-b border-gray-200 text-gray-500"><th className="text-left pb-2 font-medium">Description</th><th className="text-right pb-2 font-medium w-24">Max Qty</th><th className="text-right pb-2 font-medium w-28">Return Qty</th><th className="text-left pb-2 font-medium w-40">Reason</th></tr></thead>
          <tbody>
            {lines.length === 0 ? <tr><td colSpan={4} className="py-4 text-center text-gray-400">Select a Receiving Report to load lines</td></tr> :
              lines.map((l, i) => (
                <tr key={l._key} className="border-b border-gray-100">
                  <td className="py-1.5 pr-2 text-gray-700">{l.description}</td>
                  <td className="py-1.5 pr-2 text-right font-mono text-gray-500">{fmt4(l.max_qty)}</td>
                  <td className="py-1.5 pr-2"><input type="number" value={l.return_qty} disabled={readOnly} onChange={e => updateLine(i, { return_qty: +e.target.value })} className="border border-gray-300 rounded px-2 py-1 text-xs text-right w-28 focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} max={l.max_qty} step="any" /></td>
                  <td className="py-1.5"><input type="text" value={l.reason} disabled={readOnly} onChange={e => updateLine(i, { reason: e.target.value })} className="border border-gray-300 rounded px-2 py-1 text-xs w-40 focus:outline-none focus:ring-1 focus:ring-gray-900" placeholder="Reason…" /></td>
                </tr>
              ))
            }
          </tbody>
        </table>
      </div>
      {!readOnly && <div className="flex justify-end gap-2"><button onClick={() => setMode('list')} className="px-4 py-2 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button><button onClick={save} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : 'Save Return'}</button></div>}
    </div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Purchase Returns</h2>
        <button onClick={() => { setEditReturn({ return_date: today() }); setLines([]); setError(''); setMode('edit') }} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New Return</button>
      </div>
      <div className="flex gap-2">
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option><option value="draft">Draft</option><option value="shipped">Shipped</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option>
        </select>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : returns.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No purchase returns found.</div> : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200"><tr>{['Return Date','Return #','Supplier','Remarks','Status',''].map(h => <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>)}</tr></thead>
            <tbody className="divide-y divide-gray-100">
              {returns.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={r.return_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{r.return_number}</td>
                  <td className="px-3 py-2 text-gray-700">{r.supplier_name_snapshot}</td>
                  <td className="px-3 py-2 text-gray-500">{r.remarks || '—'}</td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[r.status]} label={r.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => { setEditReturn({ ...r }); supabase.from('purchase_return_lines').select('*').eq('return_id', r.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id })) as ReturnLine[] || [])); setMode('view') }} className="text-blue-600 hover:text-blue-800">View</button>
                      {r.status === 'draft' && <button onClick={() => ship(r)} className="text-orange-600 hover:text-orange-800">Ship</button>}
                      {r.status === 'shipped' && <button onClick={() => complete(r)} className="text-green-600 hover:text-green-800">Complete</button>}
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
