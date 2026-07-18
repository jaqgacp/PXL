import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, DateCell } from '@/components/ui/shared'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

// ── Types ─────────────────────────────────────────────────────
type DRStatus = 'draft' | 'in_transit' | 'delivered' | 'cancelled'

type DR = {
  id: string; dr_number: string; dr_date: string
  sales_order_id: string | null; customer_id: string
  customer_name_snapshot: string; dr_date2?: string
  shipping_method: string; tracking_number: string | null; driver_name: string | null
  delivery_address: string; status: DRStatus; branch_id: string; created_at: string
}

type DRLine = {
  _key: string; id?: string; line_number: number; so_line_id: string | null
  item_id: string; description: string
  quantity: number; uom_id: string; lot_serial_no: string
}

type CustomerRef = { id: string; registered_name: string; address: string | null }
type ItemRef = { id: string; item_code: string; item_name: string; default_uom_id: string | null }
type UOMRef = { id: string; uom_code: string; uom_name: string }
type SORef = { id: string; so_number: string; customer_id: string; customer_name_snapshot: string }
type SOLineRef = { id: string; sales_order_id: string; item_id: string | null; description: string; quantity: number; fulfilled_quantity: number; uom_id: string | null; line_number: number }
type Branch = { id: string; branch_code: string; branch_name: string }

// ── Helpers ───────────────────────────────────────────────────
const today = () => new Date().toISOString().split('T')[0]
const newLine = (idx = 0): DRLine => ({
  _key: crypto.randomUUID(), line_number: idx + 1, so_line_id: null,
  item_id: '', description: '', quantity: 1, uom_id: '', lot_serial_no: '',
})


const statusMap: Record<DRStatus, string> = {
  draft: 'draft', in_transit: 'warning', delivered: 'posted', cancelled: 'error',
}
const statusLabel: Record<DRStatus, string> = {
  draft: 'Draft', in_transit: 'In Transit', delivered: 'Delivered', cancelled: 'Cancelled',
}

export default function DeliveryReceiptsPage() {
  const { companyId, branchId } = useAppCtx()

  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [uoms, setUOMs] = useState<UOMRef[]>([])
  const [salesOrders, setSalesOrders] = useState<SORef[]>([])
  const [branches, setBranches] = useState<Branch[]>([])

  const [list, setList] = useState<DR[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<DRStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const PAGE = 25

  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editDoc, setEditDoc] = useState<DR | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fSO, setFSO] = useState('')
  const [fDate, setFDate] = useState(today())
  const [fBranch, setFBranch] = useState(branchId)
  const [fShipping, setFShipping] = useState<'courier' | 'in_house' | 'pickup'>('in_house')
  const [fTracking, setFTracking] = useState('')
  const [fDriver, setFDriver] = useState('')
  const [fAddress, setFAddress] = useState('')
  const [lines, setLines] = useState<DRLine[]>([newLine(0)])

  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,address:delivery_address')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('items').select('id,item_code,item_name:description,default_uom_id:uom_id')
        .eq('company_id', companyId).eq('is_active', true).order('description'),
      supabase.from('units_of_measure').select('id,uom_code,uom_name:description').eq('is_active', true).order('uom_code'),
      supabase.from('sales_orders').select('id,so_number,customer_id,customer_name_snapshot')
        .eq('company_id', companyId).eq('approval_status', 'approved')
        .in('fulfillment_status', ['open', 'partial']).order('so_date', { ascending: false }),
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true),
    ]).then(([{ data: cs }, { data: is }, { data: us }, { data: sos }, { data: bs }]) => {
      setCustomers(cs as CustomerRef[] || [])
      setItems(is as ItemRef[] || [])
      setUOMs(us as UOMRef[] || [])
      setSalesOrders(sos as SORef[] || [])
      setBranches(bs as Branch[] || [])
    })
  }, [companyId])

  const loadList = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('delivery_receipts').select('*', { count: 'exact' })
      .eq('company_id', companyId).order('dr_date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)
    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`dr_number.ilike.${s},customer_name_snapshot.ilike.${s}`)
    }
    const { data, count } = await q
    setList(data as DR[] || [])
    setTotalCount(count || 0)
    setLoading(false)
  }, [companyId, page, filterStatus, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  const onCustomerChange = (id: string) => {
    const c = customers.find(x => x.id === id)
    setFCustomer(id)
    setFCustomerName(c?.registered_name || '')
    setFAddress(c?.address || '')
  }

  const onSOChange = async (soId: string) => {
    setFSO(soId)
    if (!soId) return
    const so = salesOrders.find(s => s.id === soId)
    if (!so) return
    setFCustomer(so.customer_id)
    setFCustomerName(so.customer_name_snapshot)
    const cust = customers.find(c => c.id === so.customer_id)
    if (cust) setFAddress(cust.address || '')
    const { data: solns } = await supabase.from('sales_order_lines').select('*')
      .eq('sales_order_id', soId).order('line_number')
    if (solns && solns.length) {
      setLines((solns as SOLineRef[]).map(l => ({
        _key: crypto.randomUUID(), line_number: l.line_number, so_line_id: l.id,
        item_id: l.item_id || '', description: l.description,
        quantity: Math.max(0, l.quantity - l.fulfilled_quantity),
        uom_id: l.uom_id || '', lot_serial_no: '',
      })).filter(l => l.quantity > 0))
    }
  }

  const setLineField = (key: string, field: keyof DRLine, value: string | number) => {
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      if (field === 'item_id') {
        const item = items.find(i => i.id === value)
        return { ...l, item_id: value as string, description: item?.item_name || l.description, uom_id: item?.default_uom_id || l.uom_id }
      }
      return { ...l, [field]: value }
    }))
  }

  const openNew = () => {
    setEditDoc(null); setFCustomer(''); setFCustomerName(''); setFSO('')
    setFDate(today()); setFBranch(branchId); setFShipping('in_house')
    setFTracking(''); setFDriver(''); setFAddress(''); setLines([newLine(0)]); setError('')
    setMode('new')
  }

  const openEdit = async (doc: DR) => {
    setEditDoc(doc)
    setFCustomer(doc.customer_id); setFCustomerName(doc.customer_name_snapshot)
    setFSO(doc.sales_order_id || ''); setFDate(doc.dr_date); setFBranch(doc.branch_id)
    setFShipping(doc.shipping_method as typeof fShipping)
    setFTracking(doc.tracking_number || ''); setFDriver(doc.driver_name || '')
    setFAddress(doc.delivery_address); setError('')
    const { data: lns } = await supabase.from('delivery_receipt_lines').select('*').eq('dr_id', doc.id).order('line_number')
    if (lns && lns.length) setLines(lns.map(l => ({ _key: l.id, id: l.id, line_number: l.line_number, so_line_id: l.so_line_id, item_id: l.item_id || '', description: l.description, quantity: Number(l.quantity), uom_id: l.uom_id || '', lot_serial_no: l.lot_serial_no || '' })))
    else setLines([newLine(0)])
    setMode(doc.status === 'draft' || doc.status === 'in_transit' ? 'edit' : 'view')
  }

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  // Delivery receipts allocate a number series but do not post to the GL — no open-period gate.
  const readiness = useTransactionReadiness({
    companyId,
    branchId: fBranch || branchId,
    documentCode: 'DR',
    postingDate: fDate,
    requiredConfig,
    requireOpenPeriod: false,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0

  const save = async (nextStatus: DRStatus) => {
    if (setupBlocked) { setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0]); return }
    if (!companyId || !fCustomer) { setError('Customer is required.'); return }
    if (!fAddress.trim()) { setError('Delivery address is required.'); return }
    if (lines.every(l => !l.description.trim())) { setError('At least one line item is required.'); return }
    setSaving(true); setError('')
    try {
      const isNew = mode === 'new'
      let docNum = editDoc?.dr_number || ''
      if (isNew) {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', {
          p_company_id: companyId, p_branch_id: fBranch || branchId, p_document_code: 'DR',
        })
        if (ne || !num) throw new Error(ne?.message || 'No number series for Delivery Receipts (code: DR). Configure in Number Series setup.')
        docNum = num as string
      }
      const payload = {
        company_id: companyId, branch_id: fBranch || branchId,
        sales_order_id: fSO || null, customer_id: fCustomer, customer_name_snapshot: fCustomerName,
        dr_number: docNum, dr_date: fDate, shipping_method: fShipping,
        tracking_number: fTracking || null, driver_name: fDriver || null,
        delivery_address: fAddress, status: nextStatus,
        ...(nextStatus === 'delivered' ? { delivered_at: new Date().toISOString() } : {}),
      }
      let docId = editDoc?.id
      if (isNew) {
        const { data: ins, error: ie } = await supabase.from('delivery_receipts').insert(payload).select('id').single()
        if (ie) throw ie; docId = ins.id
      } else {
        const { error: ue } = await supabase.from('delivery_receipts').update(payload).eq('id', docId!)
        if (ue) throw ue
      }
      const validLines = lines.filter(l => l.description.trim() && l.quantity > 0)
      await supabase.from('delivery_receipt_lines').delete().eq('dr_id', docId!)
      if (validLines.length) {
        const { error: le } = await supabase.from('delivery_receipt_lines').insert(
          validLines.map((l, i) => ({
            dr_id: docId!, company_id: companyId, line_number: i + 1,
            so_line_id: l.so_line_id, item_id: l.item_id || null,
            description: l.description, quantity: l.quantity,
            uom_id: l.uom_id || null, lot_serial_no: l.lot_serial_no || null,
          }))
        )
        if (le) throw le
      }
      setMode('list')
    } catch (e) { setError(e instanceof Error ? e.message : 'Save failed.') }
    setSaving(false)
  }

  const readOnly = mode === 'view'
  const canEdit = mode === 'new' || mode === 'edit'
  const drStatus = editDoc?.status || 'draft'

  // ── List ────────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search DR#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as DRStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            <option value="">All Statuses</option>
            {(['draft','in_transit','delivered','cancelled'] as DRStatus[]).map(s => (
              <option key={s} value={s}>{statusLabel[s]}</option>
            ))}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={openNew} className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Delivery Receipt
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Delivery Receipts.</div>
        ) : loading ? (
          <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Delivery Receipts found</p>
            <p className="text-xs text-gray-400 mt-1">{search || filterStatus ? 'No records match the current filters.' : 'Create a Delivery Receipt to track outbound shipments.'}</p>
            {!search && !filterStatus && <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">New Delivery Receipt</button>}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['DR Date','DR Number','Customer','Source SO','Shipping Method','Tracking No.','Status'].map(h => (
                    <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {list.map(dr => (
                  <tr key={dr.id} onClick={() => openEdit(dr)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                    <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={dr.dr_date} /></td>
                    <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{dr.dr_number}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{dr.customer_name_snapshot}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500">{dr.sales_order_id ? salesOrders.find(s => s.id === dr.sales_order_id)?.so_number || '—' : '—'}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500 capitalize">{dr.shipping_method.replace('_', ' ')}</td>
                    <td className="px-4 py-2.5 text-xs font-mono text-gray-400">{dr.tracking_number || '—'}</td>
                    <td className="px-4 py-2.5"><StatusBadge status={statusMap[dr.status]} label={statusLabel[dr.status]} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    )
  }

  // ── Form ────────────────────────────────────────────────────
  return (
    <LegacyTransactionWorkspace title="Delivery Receipt" family="sales" pattern="B" posting={false}
      documentNo={editDoc?.dr_number} status={drStatus} identity={fCustomerName}
      financialFacts={[{ label: 'Quantity for Delivery', value: lines.reduce((sum, line) => sum + Number(line.quantity || 0), 0), hint: 'Operational quantity; no value is inferred' }, { label: 'Line Count', value: lines.length }]}
      contextFacts={[{ label: 'Customer', value: fCustomerName || 'Not selected' }, { label: 'Delivery Date', value: fDate }, { label: 'Shipping Method', value: fShipping }, { label: 'Tracking Reference', value: fTracking || 'Not assigned' }]}
      relatedFacts={[{ label: 'Source Sales Order', value: fSO || 'Not linked', hint: fSO ? 'Fulfillment source' : 'No source selected', to: '/sales-orders' }]}
      sourceDocId={editDoc?.id} auditTable="delivery_receipts" onBack={() => setMode('list')} backLabel="Delivery Receipts"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list') },
        { key: 'save', label: saving ? 'Saving…' : drStatus === 'in_transit' ? 'Update' : 'Save Draft', onClick: () => save(drStatus === 'in_transit' ? 'in_transit' : 'draft'), disabled: saving, hidden: readOnly || !['draft','in_transit'].includes(drStatus) },
        { key: 'advance', label: drStatus === 'in_transit' ? 'Confirm Delivered' : 'Dispatch', onClick: () => save(drStatus === 'in_transit' ? 'delivered' : 'in_transit'), disabled: saving, hidden: readOnly || !['draft','in_transit'].includes(drStatus), variant: 'primary' },
      ]}
      headerFields={[
        { key: 'number', label: 'Delivery Receipt Number', card: 0, content: <div className="pxl-readonly-field">{editDoc?.dr_number || 'Auto-assigned on save'}</div> },
        { key: 'date', label: 'Delivery Date *', card: 0, content: <input type="date" value={fDate} onChange={e => setFDate(e.target.value)} disabled={readOnly} className="pxl-input w-full" /> },
        { key: 'branch', label: 'Branch', card: 0, content: readOnly ? <div className="pxl-readonly-field">{branches.find(b => b.id === fBranch)?.branch_name || '—'}</div> : <select value={fBranch} onChange={e => setFBranch(e.target.value)} className="pxl-input w-full"><option value="">Select branch…</option>{branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} – {b.branch_name}</option>)}</select> },
        { key: 'customer', label: 'Customer *', card: 1, span: 2, content: readOnly || !!fSO ? <div className="pxl-readonly-field">{fCustomerName || '—'}</div> : <select value={fCustomer} onChange={e => onCustomerChange(e.target.value)} className="pxl-input w-full"><option value="">Select customer…</option>{customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}</select> },
        { key: 'address', label: 'Delivery Address *', card: 1, span: 2, content: readOnly ? <div className="pxl-readonly-field">{fAddress || '—'}</div> : <input value={fAddress} onChange={e => setFAddress(e.target.value)} className="pxl-input w-full" /> },
        { key: 'source', label: 'Source Sales Order', card: 2, content: readOnly ? <div className="pxl-readonly-field">{salesOrders.find(s => s.id === fSO)?.so_number || '—'}</div> : <select value={fSO} onChange={e => onSOChange(e.target.value)} className="pxl-input w-full"><option value="">None (standalone)</option>{salesOrders.map(s => <option key={s.id} value={s.id}>{s.so_number} — {s.customer_name_snapshot}</option>)}</select> },
        { key: 'shipping', label: 'Shipping Method *', card: 2, content: readOnly ? <div className="pxl-readonly-field">{fShipping.replace('_', ' ')}</div> : <select value={fShipping} onChange={e => setFShipping(e.target.value as typeof fShipping)} className="pxl-input w-full"><option value="in_house">In-House</option><option value="courier">Courier</option><option value="pickup">Customer Pickup</option></select> },
        { key: 'tracking', label: 'Tracking Number', card: 2, content: readOnly ? <div className="pxl-readonly-field">{fTracking || '—'}</div> : <input value={fTracking} onChange={e => setFTracking(e.target.value)} className="pxl-input w-full" /> },
        { key: 'driver', label: 'Driver / Personnel', card: 2, content: readOnly ? <div className="pxl-readonly-field">{fDriver || '—'}</div> : <input value={fDriver} onChange={e => setFDriver(e.target.value)} className="pxl-input w-full" /> },
      ]}
      tabContent={{ validation: <div className="space-y-2">{canEdit && <SetupReadinessBanner readiness={readiness} />}{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}</div> }}>
    <div>
      <div className="divide-y divide-gray-200">
        <div className="bg-white">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
            <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Items to Deliver</span>
            {canEdit && !fSO && (
              <button type="button" onClick={() => setLines(prev => [...prev, newLine(prev.length)])}
                className="flex items-center gap-1 text-xs text-gray-500 hover:text-gray-900 border border-gray-300 rounded px-2 py-1 hover:bg-gray-50">
                <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
                Add Line
              </button>
            )}
          </div>
          <div className="overflow-x-auto">
            <table className="pxl-data-grid w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-8">#</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[160px]">Item</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[200px]">Description</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">Qty to Deliver</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-16">UOM</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[140px]">Lot / Serial No.</th>
                  {canEdit && !fSO && <th className="px-2 w-8" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {lines.map((l, idx) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-4 py-2.5 text-xs text-gray-400 text-right">{idx + 1}</td>
                    <td className="px-4 py-2.5">
                      {canEdit && !fSO ? (
                        <select value={l.item_id} onChange={e => setLineField(l._key, 'item_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">— Select item —</option>
                          {items.map(i => <option key={i.id} value={i.id}>{i.item_code} — {i.item_name}</option>)}
                        </select>
                      ) : <span className="text-xs text-gray-600">{items.find(i => i.id === l.item_id)?.item_name || l.description}</span>}
                    </td>
                    <td className="px-4 py-2.5">
                      {canEdit ? <input value={l.description} onChange={e => setLineField(l._key, 'description', e.target.value)} className="w-full bg-transparent border-0 text-sm py-0 px-0 focus:outline-none" placeholder="Description…" />
                        : <span className="text-xs text-gray-700">{l.description}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right">
                      {canEdit ? <input type="number" value={l.quantity} min={0} step="any" onChange={e => setLineField(l._key, 'quantity', parseFloat(e.target.value) || 0)} className="w-20 text-right bg-transparent border-0 text-sm focus:outline-none" />
                        : <span className="text-xs font-mono tabular-nums">{l.quantity}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-gray-500">
                      {canEdit && !fSO ? (
                        <select value={l.uom_id} onChange={e => setLineField(l._key, 'uom_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">—</option>
                          {uoms.map(u => <option key={u.id} value={u.id}>{u.uom_code}</option>)}
                        </select>
                      ) : <span>{uoms.find(u => u.id === l.uom_id)?.uom_code || '—'}</span>}
                    </td>
                    <td className="px-4 py-2.5">
                      {canEdit ? <input value={l.lot_serial_no} onChange={e => setLineField(l._key, 'lot_serial_no', e.target.value)} className="w-full bg-transparent border-0 text-xs py-0 px-0 focus:outline-none text-gray-500" placeholder="Lot / serial #…" />
                        : <span className="text-xs font-mono text-gray-400">{l.lot_serial_no || '—'}</span>}
                    </td>
                    {canEdit && !fSO && (
                      <td className="px-2 py-2.5">
                        <button type="button" onClick={() => setLines(prev => prev.filter(x => x._key !== l._key))} className="text-gray-300 hover:text-red-500">
                          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M18 6L6 18M6 6l12 12" /></svg>
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    </LegacyTransactionWorkspace>
  )
}
