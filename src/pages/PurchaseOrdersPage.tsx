import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

type POStatus = 'draft' | 'approved' | 'partially_received' | 'fully_received' | 'cancelled'

type PO = {
  id: string; company_id: string; branch_id: string | null
  po_number: string; po_date: string; supplier_id: string
  supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  delivery_address: string | null; expected_date: string | null
  payment_terms_id: string | null; currency_code: string
  notes: string | null; total_amount: number; status: POStatus
  created_at: string
}

type POLine = {
  _key: string; id?: string
  item_id: string; description: string
  quantity: number; uom_id: string; uom_label: string
  unit_price: number; total_amount: number
}

type SupplierRef = {
  id: string; registered_name: string; tin: string
  registered_address: string; default_terms_id: string | null
}
type ItemRef = { id: string; item_code: string; description: string; uom_id: string; uom_label: string; standard_cost: number }
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const newLine = (): POLine => ({
  _key: crypto.randomUUID(), item_id: '', description: '',
  quantity: 1, uom_id: '', uom_label: '', unit_price: 0, total_amount: 0,
})

export default function PurchaseOrdersPage() {
  const { companyId, branchId } = useAppCtx()
  const [orders, setOrders] = useState<PO[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editPO, setEditPO] = useState<Partial<PO> | null>(null)
  const [lines, setLines] = useState<POLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'

  const loadOrders = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('purchase_orders').select('*').eq('company_id', companyId).order('po_date', { ascending: false }).order('po_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`po_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setOrders(data as PO[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadOrders() }, [loadOrders, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('suppliers').select('id,registered_name,tin,registered_address,default_terms_id').eq('company_id', companyId).eq('is_active', true).order('registered_name')
      .then(({ data }) => setSuppliers(data as SupplierRef[] || []))
    supabase.from('items').select('id,item_code,description,uom_id,uom:units_of_measure(uom_name),standard_cost').eq('company_id', companyId).eq('is_active', true).order('description')
      .then(({ data }) => setItems((data || []).map((i: any) => ({ ...i, uom_label: i.uom?.uom_name || '' }))))
  }, [companyId])

  const openNew = () => {
    setEditPO({ po_date: today(), currency_code: 'PHP', branch_id: branchId || '' })
    setLines([newLine()])
    setError('')
    setMode('edit')
    setTimeout(() => listRef.current?.scrollTo(0, 0), 10)
  }

  const openEdit = (po: PO) => {
    setEditPO({ ...po })
    supabase.from('purchase_order_lines').select('*').eq('po_id', po.id).order('line_number')
      .then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, uom_label: '' })) as POLine[] || [newLine()]))
    setError('')
    setMode('edit')
  }

  const openView = (po: PO) => {
    setEditPO({ ...po })
    supabase.from('purchase_order_lines').select('*').eq('po_id', po.id).order('line_number')
      .then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, uom_label: '' })) as POLine[] || []))
    setMode('view')
  }

  const selectSupplier = (id: string) => {
    const s = suppliers.find(x => x.id === id)
    if (!s) return
    setEditPO(prev => ({ ...prev, supplier_id: s.id, supplier_name_snapshot: s.registered_name, supplier_tin_snapshot: s.tin, delivery_address: s.registered_address, payment_terms_id: s.default_terms_id || '' }))
  }

  const selectItem = (idx: number, id: string) => {
    const item = items.find(x => x.id === id)
    if (!item) return
    updateLine(idx, { item_id: item.id, description: item.description, uom_id: item.uom_id, uom_label: item.uom_label, unit_price: item.standard_cost })
  }

  const updateLine = (idx: number, patch: Partial<POLine>) => {
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      const updated = { ...l, ...patch }
      updated.total_amount = Math.round(updated.quantity * updated.unit_price * 100) / 100
      return updated
    }))
  }

  const grandTotal = lines.reduce((s, l) => s + (l.total_amount || 0), 0)

  const save = async () => {
    if (!companyId || !editPO?.supplier_id) { setError('Supplier is required'); return }
    setSaving(true); setError('')
    try {
      const id = await supabase.rpc('fn_save_purchase_order', {
        p_po_id: editPO.id || null,
        p_header: {
          company_id: companyId, branch_id: branchId || editPO.branch_id || null,
          supplier_id: editPO.supplier_id, supplier_name_snapshot: editPO.supplier_name_snapshot,
          supplier_tin_snapshot: editPO.supplier_tin_snapshot || '',
          po_date: editPO.po_date, delivery_address: editPO.delivery_address || '',
          expected_date: editPO.expected_date || '', payment_terms_id: editPO.payment_terms_id || '',
          currency_code: editPO.currency_code || 'PHP', notes: editPO.notes || '',
        },
        p_lines: lines.filter(l => l.description.trim()).map(l => ({
          item_id: l.item_id || null, description: l.description,
          quantity: l.quantity, uom_id: l.uom_id || null, unit_price: l.unit_price,
        })),
      })
      if (id.error) throw new Error(id.error.message)
      setMode('list'); loadOrders()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const approve = async (po: PO) => {
    const { error: e } = await supabase.rpc('fn_approve_purchase_order', { p_po_id: po.id })
    if (e) { alert(e.message); return }
    loadOrders()
  }

  const cancel = async (po: PO) => {
    if (!confirm(`Cancel PO ${po.po_number}?`)) return
    const { error: e } = await supabase.rpc('fn_cancel_purchase_order', { p_po_id: po.id })
    if (e) { alert(e.message); return }
    loadOrders()
  }

  const STATUS_COLORS: Record<string, string> = {
    draft: 'draft', approved: 'approved', partially_received: 'warning',
    fully_received: 'posted', cancelled: 'error',
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50 disabled:text-gray-500'

  if (mode !== 'list') return (
    <div className="space-y-4" ref={listRef}>
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-gray-900">{editPO?.id ? (readOnly ? 'Purchase Order' : 'Edit PO') : 'New Purchase Order'}</h2>
          {editPO?.po_number && <p className="text-xs text-gray-500 mt-0.5">{editPO.po_number} · <StatusBadge status={STATUS_COLORS[editPO.status as string] || 'draft'} label={editPO.status as string} /></p>}
        </div>
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-700">← Back</button>
      </div>

      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}

      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Header</h3>
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">PO Date *</label>
            <input type="date" value={editPO?.po_date || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, po_date: e.target.value }))} className={inp} />
          </div>
          <div className="col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">Supplier *</label>
            <select value={editPO?.supplier_id || ''} disabled={readOnly} onChange={e => selectSupplier(e.target.value)} className={inp + ' w-full'}>
              <option value="">— Select supplier —</option>
              {suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Expected Delivery</label>
            <input type="date" value={editPO?.expected_date || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, expected_date: e.target.value }))} className={inp} />
          </div>
          <div className="col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">Delivery Address</label>
            <input type="text" value={editPO?.delivery_address || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, delivery_address: e.target.value }))} className={inp + ' w-full'} />
          </div>
          <div className="col-span-3">
            <label className="block text-xs font-medium text-gray-700 mb-1">Notes</label>
            <textarea value={editPO?.notes || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, notes: e.target.value }))} rows={2} className={inp + ' w-full resize-none'} />
          </div>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Line Items</h3>
          {!readOnly && <button onClick={() => setLines(l => [...l, newLine()])} className="text-xs text-blue-600 hover:text-blue-800 font-medium">+ Add Line</button>}
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200 text-gray-500">
                <th className="text-left pb-2 font-medium w-48">Item</th>
                <th className="text-left pb-2 font-medium">Description</th>
                <th className="text-right pb-2 font-medium w-20">Qty</th>
                <th className="text-right pb-2 font-medium w-28">Unit Price</th>
                <th className="text-right pb-2 font-medium w-28">Total</th>
                {!readOnly && <th className="w-8" />}
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={l._key} className="border-b border-gray-100">
                  <td className="py-1.5 pr-2">
                    <select value={l.item_id} disabled={readOnly} onChange={e => selectItem(i, e.target.value)} className={inp + ' w-full text-xs'}>
                      <option value="">— Item —</option>
                      {items.map(it => <option key={it.id} value={it.id}>{it.item_code} — {it.description}</option>)}
                    </select>
                  </td>
                  <td className="py-1.5 pr-2"><input value={l.description} disabled={readOnly} onChange={e => updateLine(i, { description: e.target.value })} className={inp + ' w-full text-xs'} placeholder="Description" /></td>
                  <td className="py-1.5 pr-2"><input type="number" value={l.quantity} disabled={readOnly} onChange={e => updateLine(i, { quantity: +e.target.value })} className={inp + ' w-20 text-right text-xs'} min={0} step="any" /></td>
                  <td className="py-1.5 pr-2"><input type="number" value={l.unit_price} disabled={readOnly} onChange={e => updateLine(i, { unit_price: +e.target.value })} className={inp + ' w-28 text-right text-xs'} min={0} step="any" /></td>
                  <td className="py-1.5 text-right font-mono text-xs">{fmt(l.total_amount)}</td>
                  {!readOnly && <td className="py-1.5 pl-2"><button onClick={() => setLines(p => p.filter((_, j) => j !== i))} className="text-gray-300 hover:text-red-500 text-sm">×</button></td>}
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-gray-300 font-semibold">
                <td colSpan={4} className="pt-2 text-right text-xs text-gray-600 pr-2">Total Amount</td>
                <td className="pt-2 text-right font-mono text-sm">{fmt(grandTotal)}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>

      {!readOnly && (
        <div className="flex justify-end gap-2">
          <button onClick={() => setMode('list')} className="px-4 py-2 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
          <button onClick={save} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">
            {saving ? 'Saving…' : 'Save PO'}
          </button>
        </div>
      )}
    </div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Purchase Orders</h2>
        <button onClick={openNew} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New PO</button>
      </div>

      <div className="flex gap-2">
        <input placeholder="Search PO # or supplier…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option>
          <option value="draft">Draft</option>
          <option value="approved">Approved</option>
          <option value="partially_received">Partially Received</option>
          <option value="fully_received">Fully Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : orders.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No purchase orders found.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['PO Date','PO Number','Supplier','Expected Date','Total Amount','Status',''].map(h => (
                  <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {orders.map(po => (
                <tr key={po.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={po.po_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{po.po_number}</td>
                  <td className="px-3 py-2 text-gray-700">{po.supplier_name_snapshot}</td>
                  <td className="px-3 py-2"><DateCell date={po.expected_date} /></td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={po.total_amount} /></td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[po.status]} label={po.status.replace('_', ' ')} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => openView(po)} className="text-blue-600 hover:text-blue-800">View</button>
                      {po.status === 'draft' && <button onClick={() => openEdit(po)} className="text-gray-600 hover:text-gray-800">Edit</button>}
                      {po.status === 'draft' && <button onClick={() => approve(po)} className="text-green-600 hover:text-green-800">Approve</button>}
                      {['draft','approved','partially_received'].includes(po.status) && <button onClick={() => cancel(po)} className="text-red-600 hover:text-red-800">Cancel</button>}
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
