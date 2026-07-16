import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, DateCell } from '@/components/ui/shared'
import { transactionHeaderClass } from '@/lib/transactionWorkspace'

type RRStatus = 'draft' | 'received' | 'cancelled'

type RR = {
  id: string; company_id: string; rr_number: string; rr_date: string
  po_id: string; supplier_id: string; supplier_name_snapshot: string
  supplier_dr_no: string | null; remarks: string | null
  status: RRStatus; created_at: string
}

type RRLine = {
  _key: string; id?: string
  po_line_id: string; item_id: string; description: string
  ordered_qty: number; received_qty: number; reject_qty: number
  uom_id: string; unit_price: number
}

type PORef = {
  id: string; po_number: string; supplier_id: string
  supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  status: string
}

type POLine = {
  id: string; item_id: string; description: string; quantity: number
  uom_id: string; unit_price: number
  items?: { description: string; uom_id: string }
  units_of_measure?: { uom_name: string }
}

const today = () => new Date().toISOString().split('T')[0]

export default function ReceivingReportsPage() {
  const { companyId, branchId } = useAppCtx()
  const [reports, setReports] = useState<RR[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editRR, setEditRR] = useState<Partial<RR> | null>(null)
  const [lines, setLines] = useState<RRLine[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [openPOs, setOpenPOs] = useState<PORef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'

  const loadReports = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('receiving_reports').select('*').eq('company_id', companyId).order('rr_date', { ascending: false }).order('rr_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`rr_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setReports(data as RR[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadReports() }, [loadReports, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('purchase_orders').select('id,po_number,supplier_id,supplier_name_snapshot,supplier_tin_snapshot,status')
      .eq('company_id', companyId).in('status', ['approved', 'partially_received']).order('po_date', { ascending: false })
      .then(({ data }) => setOpenPOs(data as PORef[] || []))
  }, [companyId])

  const loadPOLines = async (poId: string) => {
    const { data } = await supabase.from('purchase_order_lines')
      .select('id,item_id,description,quantity,uom_id,unit_price')
      .eq('po_id', poId).order('line_number')
    return (data as POLine[] || []).map(l => ({
      _key: l.id, po_line_id: l.id, item_id: l.item_id || '',
      description: l.description, ordered_qty: l.quantity,
      received_qty: l.quantity, reject_qty: 0,
      uom_id: l.uom_id || '', unit_price: l.unit_price,
    }))
  }

  const openNew = () => {
    setEditRR({ rr_date: today() })
    setLines([])
    setError('')
    setMode('edit')
  }

  const openView = (rr: RR) => {
    setEditRR({ ...rr })
    supabase.from('receiving_report_lines').select('*').eq('rr_id', rr.id).order('line_number')
      .then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id })) as RRLine[] || []))
    setMode('view')
  }

  const selectPO = async (poId: string) => {
    const po = openPOs.find(p => p.id === poId)
    if (!po) return
    setEditRR(prev => ({ ...prev, po_id: po.id }))
    const lns = await loadPOLines(po.id)
    setLines(lns)
  }

  const updateLine = (idx: number, patch: Partial<RRLine>) => {
    setLines(prev => prev.map((l, i) => i === idx ? { ...l, ...patch } : l))
  }

  const save = async () => {
    if (!companyId || !editRR?.po_id) { setError('Purchase Order is required'); return }
    if (lines.length === 0) { setError('At least one line is required'); return }
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_receiving_report', {
        p_rr_id: (editRR.id || null)!,
        p_header: {
          company_id: companyId, branch_id: branchId || null,
          po_id: editRR.po_id, rr_date: editRR.rr_date,
          supplier_dr_no: editRR.supplier_dr_no || '',
          remarks: editRR.remarks || '',
        },
        p_lines: lines.map(l => ({
          po_line_id: l.po_line_id || null, item_id: l.item_id || null,
          description: l.description, ordered_qty: l.ordered_qty,
          received_qty: l.received_qty, reject_qty: l.reject_qty || 0,
          uom_id: l.uom_id || null, unit_price: l.unit_price || 0,
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadReports()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const confirm = async (rr: RR) => {
    const { error: e } = await supabase.rpc('fn_confirm_receiving_report', { p_rr_id: rr.id })
    if (e) { alert(e.message); return }
    loadReports()
  }

  const STATUS_COLORS: Record<string, string> = {
    draft: 'draft', received: 'posted', cancelled: 'error',
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'
  const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 4, maximumFractionDigits: 4 }).format(n)

  if (mode !== 'list') return (
    <div className="space-y-4" ref={listRef}>
      <div className={`${transactionHeaderClass('purchase')} justify-between`}>
        <div>
          <h2 className="text-base font-semibold text-gray-900">{editRR?.id ? (readOnly ? 'Receiving Report' : 'Edit RR') : 'New Receiving Report'}</h2>
          {editRR?.rr_number && <p className="text-xs text-gray-500 mt-0.5">{editRR.rr_number} · <StatusBadge status={STATUS_COLORS[editRR.status as string] || 'draft'} label={editRR.status as string} /></p>}
        </div>
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-700">← Back</button>
      </div>

      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}

      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Header</h3>
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">RR Date *</label>
            <input type="date" value={editRR?.rr_date || ''} disabled={readOnly} onChange={e => setEditRR(p => ({ ...p, rr_date: e.target.value }))} className={inp} />
          </div>
          <div className="col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">Purchase Order *</label>
            <select value={editRR?.po_id || ''} disabled={readOnly || !!editRR?.id} onChange={e => selectPO(e.target.value)} className={inp + ' w-full'}>
              <option value="">— Select approved PO —</option>
              {openPOs.map(p => <option key={p.id} value={p.id}>{p.po_number} — {p.supplier_name_snapshot}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Supplier DR No.</label>
            <input type="text" value={editRR?.supplier_dr_no || ''} disabled={readOnly} onChange={e => setEditRR(p => ({ ...p, supplier_dr_no: e.target.value }))} className={inp + ' w-full'} />
          </div>
          <div className="col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">Remarks</label>
            <input type="text" value={editRR?.remarks || ''} disabled={readOnly} onChange={e => setEditRR(p => ({ ...p, remarks: e.target.value }))} className={inp + ' w-full'} />
          </div>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-3">Line Items</h3>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200 text-gray-500">
                <th className="text-left pb-2 font-medium">Description</th>
                <th className="text-right pb-2 font-medium w-24">Ordered</th>
                <th className="text-right pb-2 font-medium w-24">Received</th>
                <th className="text-right pb-2 font-medium w-24">Rejected</th>
              </tr>
            </thead>
            <tbody>
              {lines.length === 0 ? (
                <tr><td colSpan={4} className="py-4 text-center text-gray-400">Select a PO to load lines</td></tr>
              ) : lines.map((l, i) => (
                <tr key={l._key} className="border-b border-gray-100">
                  <td className="py-1.5 pr-2 text-gray-700">{l.description}</td>
                  <td className="py-1.5 pr-2 text-right font-mono text-gray-500">{fmt(l.ordered_qty)}</td>
                  <td className="py-1.5 pr-2">
                    <input type="number" value={l.received_qty} disabled={readOnly} onChange={e => updateLine(i, { received_qty: +e.target.value })} className="border border-gray-300 rounded px-2 py-1 text-xs text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} max={l.ordered_qty} step="any" />
                  </td>
                  <td className="py-1.5">
                    <input type="number" value={l.reject_qty} disabled={readOnly} onChange={e => updateLine(i, { reject_qty: +e.target.value })} className="border border-gray-300 rounded px-2 py-1 text-xs text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {!readOnly && (
        <div className="flex justify-end gap-2">
          <button onClick={() => setMode('list')} className="px-4 py-2 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
          <button onClick={save} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">
            {saving ? 'Saving…' : 'Save RR'}
          </button>
        </div>
      )}
    </div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Receiving Reports</h2>
        <button onClick={openNew} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New RR</button>
      </div>

      <div className="flex gap-2">
        <input placeholder="Search RR # or supplier…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option>
          <option value="draft">Draft</option>
          <option value="received">Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : reports.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No receiving reports found.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['RR Date','RR Number','Supplier','Supplier DR No.','Status',''].map(h => (
                  <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {reports.map(rr => (
                <tr key={rr.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={rr.rr_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{rr.rr_number}</td>
                  <td className="px-3 py-2 text-gray-700">{rr.supplier_name_snapshot}</td>
                  <td className="px-3 py-2 text-gray-500">{rr.supplier_dr_no || '—'}</td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[rr.status]} label={rr.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => openView(rr)} className="text-blue-600 hover:text-blue-800">View</button>
                      {rr.status === 'draft' && <button onClick={() => confirm(rr)} className="text-green-600 hover:text-green-800">Confirm</button>}
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
