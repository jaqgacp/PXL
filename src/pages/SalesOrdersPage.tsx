import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { composePhTin } from '@/lib/philippines'
import { transactionHeaderClass } from '@/lib/transactionWorkspace'

// ── Types ─────────────────────────────────────────────────────
type SOApproval = 'pending' | 'approved' | 'rejected'
type SOFulfill  = 'open' | 'partial' | 'fulfilled' | 'cancelled'

type SO = {
  id: string; so_number: string; so_date: string; expected_delivery_date: string | null
  customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string
  quotation_id: string | null; currency_code: string
  reference_number: string | null; remarks: string | null
  total_amount: number; approval_status: SOApproval; fulfillment_status: SOFulfill
  branch_id: string; created_at: string
}

type SOLine = {
  _key: string; id?: string; line_number: number; quotation_line_id: string | null
  item_id: string; description: string
  quantity: number; fulfilled_quantity: number; uom_id: string
  unit_price: number; discount_amount: number; net_amount: number
}

type CustomerRef = { id: string; registered_name: string; tin: string; tin_branch_code: string }
type ItemRef = { id: string; item_code: string; item_name: string; default_uom_id: string | null; default_sales_price: number | null }
type UOMRef = { id: string; uom_code: string; uom_name: string }
type QuotationRef = { id: string; quotation_number: string; customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string; currency_code: string; status: string }
type Branch = { id: string; branch_code: string; branch_name: string }

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const newLine = (idx = 0): SOLine => ({
  _key: crypto.randomUUID(), line_number: idx + 1, quotation_line_id: null,
  item_id: '', description: '', quantity: 1, fulfilled_quantity: 0, uom_id: '',
  unit_price: 0, discount_amount: 0, net_amount: 0,
})
const computeNet = (l: SOLine): SOLine => ({
  ...l, net_amount: Math.max(0, l.quantity * l.unit_price - l.discount_amount),
})

const inp = 'w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'
const ro  = 'w-full border border-gray-200 rounded px-2.5 py-1.5 text-sm bg-gray-50 text-gray-600 cursor-default'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

const approvalBadge: Record<SOApproval, string> = { pending: 'draft', approved: 'approved', rejected: 'error' }
const fulfillBadge: Record<SOFulfill,  string> = { open: 'draft', partial: 'warning', fulfilled: 'posted', cancelled: 'error' }

export default function SalesOrdersPage() {
  const { companyId, branchId } = useAppCtx()

  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [uoms, setUOMs] = useState<UOMRef[]>([])
  const [quotations, setQuotations] = useState<QuotationRef[]>([])
  const [branches, setBranches] = useState<Branch[]>([])

  const [list, setList] = useState<SO[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterApproval, setFilterApproval] = useState<SOApproval | ''>('')
  const [filterFulfill, setFilterFulfill] = useState<SOFulfill | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const PAGE = 25

  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editDoc, setEditDoc] = useState<SO | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fQuotation, setFQuotation] = useState('')
  const [fDate, setFDate] = useState(today())
  const [fDeliveryDate, setFDeliveryDate] = useState('')
  const [fBranch, setFBranch] = useState(branchId)
  const [fCurrency, setFCurrency] = useState('PHP')
  const [fRef, setFRef] = useState('')
  const [fRemarks, setFRemarks] = useState('')
  const [lines, setLines] = useState<SOLine[]>([newLine(0)])

  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,tin,tin_branch_code')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('items').select('id,item_code,item_name:description,default_uom_id:uom_id,default_sales_price:standard_selling_price')
        .eq('company_id', companyId).eq('is_active', true).order('description'),
      supabase.from('units_of_measure').select('id,uom_code,uom_name:description').eq('is_active', true).order('uom_code'),
      supabase.from('sales_quotations').select('id,quotation_number,customer_id,customer_name_snapshot,customer_tin_snapshot,currency_code,status')
        .eq('company_id', companyId).eq('status', 'approved').order('quotation_date', { ascending: false }),
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true),
    ]).then(([{ data: cs }, { data: is }, { data: us }, { data: qs }, { data: bs }]) => {
      setCustomers(cs as CustomerRef[] || [])
      setItems(is as ItemRef[] || [])
      setUOMs(us as UOMRef[] || [])
      setQuotations(qs as QuotationRef[] || [])
      setBranches(bs as Branch[] || [])
    })
  }, [companyId])

  const loadList = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('sales_orders').select('*', { count: 'exact' })
      .eq('company_id', companyId).order('so_date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)
    if (filterApproval) q = q.eq('approval_status', filterApproval)
    if (filterFulfill) q = q.eq('fulfillment_status', filterFulfill)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`so_number.ilike.${s},customer_name_snapshot.ilike.${s}`)
    }
    const { data, count } = await q
    setList(data as SO[] || [])
    setTotalCount(count || 0)
    setLoading(false)
  }, [companyId, page, filterApproval, filterFulfill, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  const onCustomerChange = (id: string) => {
    const c = customers.find(x => x.id === id)
    setFCustomer(id)
    setFCustomerName(c?.registered_name || '')
    setFCustomerTIN(c ? composePhTin(c.tin, c.tin_branch_code) : '')
  }

  const onQuotationChange = async (qid: string) => {
    setFQuotation(qid)
    if (!qid) return
    const qt = quotations.find(q => q.id === qid)
    if (!qt) return
    setFCustomer(qt.customer_id)
    setFCustomerName(qt.customer_name_snapshot)
    setFCustomerTIN(qt.customer_tin_snapshot)
    setFCurrency(qt.currency_code)
    const { data: lns } = await supabase.from('sales_quotation_lines').select('*').eq('quotation_id', qid).order('line_number')
    if (lns && lns.length) {
      setLines(lns.map(l => computeNet({
        _key: crypto.randomUUID(), line_number: l.line_number, quotation_line_id: l.id,
        item_id: l.item_id || '', description: l.description,
        quantity: Number(l.quantity), fulfilled_quantity: 0, uom_id: l.uom_id || '',
        unit_price: Number(l.unit_price), discount_amount: Number(l.discount_amount), net_amount: 0,
      })))
    }
  }

  const setLineField = (key: string, field: keyof SOLine, value: string | number) => {
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      if (field === 'item_id') {
        const item = items.find(i => i.id === value)
        return computeNet({ ...l, item_id: value as string, description: item?.item_name || l.description, uom_id: item?.default_uom_id || l.uom_id, unit_price: item?.default_sales_price || l.unit_price })
      }
      return computeNet({ ...l, [field]: value })
    }))
  }

  const openNew = () => {
    setEditDoc(null); setFCustomer(''); setFCustomerName(''); setFCustomerTIN(''); setFQuotation('')
    setFDate(today()); setFDeliveryDate(''); setFBranch(branchId); setFCurrency('PHP'); setFRef(''); setFRemarks('')
    setLines([newLine(0)]); setError('')
    setMode('new')
  }

  const openEdit = async (doc: SO) => {
    setEditDoc(doc)
    setFCustomer(doc.customer_id); setFCustomerName(doc.customer_name_snapshot); setFCustomerTIN(doc.customer_tin_snapshot)
    setFQuotation(doc.quotation_id || ''); setFDate(doc.so_date); setFDeliveryDate(doc.expected_delivery_date || '')
    setFBranch(doc.branch_id); setFCurrency(doc.currency_code); setFRef(doc.reference_number || ''); setFRemarks(doc.remarks || ''); setError('')
    const { data: lns } = await supabase.from('sales_order_lines').select('*').eq('sales_order_id', doc.id).order('line_number')
    if (lns && lns.length) setLines(lns.map(l => ({ _key: l.id, id: l.id, line_number: l.line_number, quotation_line_id: l.quotation_line_id, item_id: l.item_id || '', description: l.description, quantity: Number(l.quantity), fulfilled_quantity: Number(l.fulfilled_quantity), uom_id: l.uom_id || '', unit_price: Number(l.unit_price), discount_amount: Number(l.discount_amount), net_amount: Number(l.net_amount) })))
    else setLines([newLine(0)])
    setMode(doc.approval_status === 'pending' ? 'edit' : 'view')
  }

  const totalAmt = lines.reduce((s, l) => s + l.net_amount, 0)

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  // Sales orders allocate a number series but do not post to the GL — no open-period gate.
  const readiness = useTransactionReadiness({
    companyId,
    branchId: fBranch || branchId,
    documentCode: 'SO',
    postingDate: fDate,
    requiredConfig,
    requireOpenPeriod: false,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0

  const save = async (nextApproval: SOApproval, nextFulfill?: SOFulfill) => {
    if (setupBlocked) { setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0]); return }
    if (!companyId || !fCustomer) { setError('Customer is required.'); return }
    if (lines.every(l => !l.description.trim())) { setError('At least one line item is required.'); return }
    setSaving(true); setError('')
    try {
      const isNew = mode === 'new'
      let docNum = editDoc?.so_number || ''
      if (isNew) {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', {
          p_company_id: companyId, p_branch_id: fBranch || branchId, p_document_code: 'SO',
        })
        if (ne || !num) throw new Error(ne?.message || 'No number series for Sales Orders (code: SO). Configure in Number Series setup.')
        docNum = num as string
      }
      const payload = {
        company_id: companyId, branch_id: fBranch || branchId,
        quotation_id: fQuotation || null, customer_id: fCustomer,
        customer_name_snapshot: fCustomerName, customer_tin_snapshot: fCustomerTIN,
        so_number: docNum, so_date: fDate, expected_delivery_date: fDeliveryDate || null,
        currency_code: fCurrency, reference_number: fRef || null, remarks: fRemarks || null,
        total_amount: totalAmt, approval_status: nextApproval,
        fulfillment_status: nextFulfill || editDoc?.fulfillment_status || 'open',
      }
      let docId = editDoc?.id
      if (isNew) {
        const { data: ins, error: ie } = await supabase.from('sales_orders').insert(payload).select('id').single()
        if (ie) throw ie; docId = ins.id
      } else {
        const { error: ue } = await supabase.from('sales_orders').update(payload).eq('id', docId!)
        if (ue) throw ue
      }
      const validLines = lines.filter(l => l.description.trim())
      await supabase.from('sales_order_lines').delete().eq('sales_order_id', docId!)
      if (validLines.length) {
        const { error: le } = await supabase.from('sales_order_lines').insert(
          validLines.map((l, i) => ({
            sales_order_id: docId!, company_id: companyId, line_number: i + 1,
            quotation_line_id: l.quotation_line_id, item_id: l.item_id || null,
            description: l.description, quantity: l.quantity, fulfilled_quantity: l.fulfilled_quantity,
            uom_id: l.uom_id || null, unit_price: l.unit_price, discount_amount: l.discount_amount, net_amount: l.net_amount,
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
  const soApproval = editDoc?.approval_status || 'pending'
  const soFulfill = editDoc?.fulfillment_status || 'open'

  // ── List ────────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search SO#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-48" />
          <select value={filterApproval} onChange={e => { setFilterApproval(e.target.value as SOApproval | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            <option value="">All Approval</option>
            {(['pending','approved','rejected'] as SOApproval[]).map(s => (
              <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
            ))}
          </select>
          <select value={filterFulfill} onChange={e => { setFilterFulfill(e.target.value as SOFulfill | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            <option value="">All Fulfillment</option>
            {(['open','partial','fulfilled','cancelled'] as SOFulfill[]).map(s => (
              <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
            ))}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={openNew} className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Sales Order
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Sales Orders.</div>
        ) : loading ? (
          <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Sales Orders found</p>
            <p className="text-xs text-gray-400 mt-1">{search || filterApproval || filterFulfill ? 'No records match the current filters.' : 'Create your first Sales Order to start fulfillment tracking.'}</p>
            {!search && !filterApproval && !filterFulfill && <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">New Sales Order</button>}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['SO Date','SO Number','Customer','Expected Delivery','Ref No.','Total Amount','Approval','Fulfillment'].map(h => (
                    <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {list.map(so => (
                  <tr key={so.id} onClick={() => openEdit(so)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                    <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={so.so_date} /></td>
                    <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{so.so_number}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{so.customer_name_snapshot}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500 whitespace-nowrap">{so.expected_delivery_date ? <DateCell date={so.expected_delivery_date} /> : '—'}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-400">{so.reference_number || '—'}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={so.total_amount} /></td>
                    <td className="px-4 py-2.5"><StatusBadge status={approvalBadge[so.approval_status]} label={so.approval_status.charAt(0).toUpperCase() + so.approval_status.slice(1)} /></td>
                    <td className="px-4 py-2.5"><StatusBadge status={fulfillBadge[so.fulfillment_status]} label={so.fulfillment_status.charAt(0).toUpperCase() + so.fulfillment_status.slice(1)} /></td>
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
    <div>
      <div className={transactionHeaderClass('sales')}>
        <button onClick={() => setMode('list')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900">
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M15 18l-6-6 6-6" /></svg>
          Sales Orders
        </button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-mono font-semibold text-gray-900">{editDoc?.so_number || 'New Sales Order'}</span>
        {editDoc && <>
          <StatusBadge status={approvalBadge[soApproval]} label={soApproval.charAt(0).toUpperCase() + soApproval.slice(1)} />
          <StatusBadge status={fulfillBadge[soFulfill]} label={soFulfill.charAt(0).toUpperCase() + soFulfill.slice(1)} />
        </>}
        <div className="flex-1" />
        {error && <span className="text-xs text-red-600 font-medium max-w-xs text-right">{error}</span>}
        {(mode === 'new' || soApproval === 'pending') && !readOnly && <>
          <button onClick={() => save('pending')} disabled={saving} className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">{saving ? 'Saving…' : 'Save'}</button>
          <button onClick={() => save('rejected')} disabled={saving} className="px-3 py-1.5 border border-red-300 text-red-600 rounded text-sm hover:bg-red-50 disabled:opacity-50">Reject</button>
          <button onClick={() => save('approved')} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">Approve</button>
        </>}
        {soApproval === 'approved' && soFulfill !== 'cancelled' && !readOnly && (
          <button onClick={() => save('approved', 'cancelled')} disabled={saving} className="px-3 py-1.5 border border-red-300 text-red-600 rounded text-sm hover:bg-red-50 disabled:opacity-50">Cancel Order</button>
        )}
      </div>

      {canEdit && (
        <div className="px-5 pt-4">
          <SetupReadinessBanner readiness={readiness} />
        </div>
      )}

      <div className="divide-y divide-gray-200">
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Sales Order Header</div>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-5 gap-y-3">
            <div><label className={lbl}>SO Number</label><div className={ro}>{editDoc?.so_number || 'Auto-assigned on save'}</div></div>
            <div>
              <label className={lbl}>SO Date <span className="text-red-500">*</span></label>
              <input type="date" value={fDate} onChange={e => setFDate(e.target.value)} disabled={readOnly} className={readOnly ? ro : inp} />
            </div>
            <div>
              <label className={lbl}>Expected Delivery Date</label>
              <input type="date" value={fDeliveryDate} onChange={e => setFDeliveryDate(e.target.value)} disabled={readOnly} className={readOnly ? ro : inp} />
            </div>
            <div>
              <label className={lbl}>Branch</label>
              {readOnly ? <div className={ro}>{branches.find(b => b.id === fBranch)?.branch_name || '—'}</div> : (
                <select value={fBranch} onChange={e => setFBranch(e.target.value)} className={inp}>
                  <option value="">Select branch…</option>
                  {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} – {b.branch_name}</option>)}
                </select>
              )}
            </div>
            <div>
              <label className={lbl}>Source Quotation</label>
              {readOnly ? <div className={ro}>{quotations.find(q => q.id === fQuotation)?.quotation_number || '—'}</div> : (
                <select value={fQuotation} onChange={e => onQuotationChange(e.target.value)} className={inp}>
                  <option value="">None (standalone)</option>
                  {quotations.map(q => <option key={q.id} value={q.id}>{q.quotation_number} — {q.customer_name_snapshot}</option>)}
                </select>
              )}
            </div>
            <div className="col-span-2">
              <label className={lbl}>Customer <span className="text-red-500">*</span></label>
              {readOnly || fQuotation ? <div className={ro}>{fCustomerName || '—'}</div> : (
                <select value={fCustomer} onChange={e => onCustomerChange(e.target.value)} className={inp}>
                  <option value="">Select customer…</option>
                  {customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                </select>
              )}
            </div>
            <div><label className={lbl}>Customer TIN</label><div className={ro}>{fCustomerTIN || '—'}</div></div>
            <div>
              <label className={lbl}>Currency</label>
              {readOnly ? <div className={ro}>{fCurrency}</div> : (
                <select value={fCurrency} onChange={e => setFCurrency(e.target.value)} className={inp}>
                  {['PHP','USD','EUR','JPY','GBP','AUD','CAD','SGD','CNY'].map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              )}
            </div>
            <div>
              <label className={lbl}>Reference No.</label>
              {readOnly ? <div className={ro}>{fRef || '—'}</div> : <input value={fRef} onChange={e => setFRef(e.target.value)} placeholder="Customer PO number" className={inp} />}
            </div>
            <div className="col-span-2 md:col-span-3">
              <label className={lbl}>Remarks</label>
              {readOnly ? <div className={ro}>{fRemarks || '—'}</div> : <textarea value={fRemarks} onChange={e => setFRemarks(e.target.value)} rows={2} className={inp + ' resize-none'} />}
            </div>
          </div>
        </div>

        <div className="bg-white">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
            <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Line Items</span>
            {canEdit && !fQuotation && (
              <button type="button" onClick={() => setLines(prev => [...prev, newLine(prev.length)])}
                className="flex items-center gap-1 text-xs text-gray-500 hover:text-gray-900 border border-gray-300 rounded px-2 py-1 hover:bg-gray-50">
                <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
                Add Line
              </button>
            )}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-8">#</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[160px]">Item / Service</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[200px]">Description</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-20">Ordered</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-20">Delivered</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-16">UOM</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">Unit Price</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-20">Discount</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">Net Amount</th>
                  {canEdit && !fQuotation && <th className="px-2 w-8" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {lines.map((l, idx) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-4 py-2.5 text-xs text-gray-400 text-right">{idx + 1}</td>
                    <td className="px-4 py-2.5">
                      {canEdit && !fQuotation ? (
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
                      {canEdit ? <input type="number" value={l.quantity} min={0} step="any" onChange={e => setLineField(l._key, 'quantity', parseFloat(e.target.value) || 0)} className="w-16 text-right bg-transparent border-0 text-sm focus:outline-none" />
                        : <span className="text-xs font-mono tabular-nums">{l.quantity}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right text-xs font-mono tabular-nums text-gray-500">{l.fulfilled_quantity}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500">
                      {canEdit && !fQuotation ? (
                        <select value={l.uom_id} onChange={e => setLineField(l._key, 'uom_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">—</option>
                          {uoms.map(u => <option key={u.id} value={u.id}>{u.uom_code}</option>)}
                        </select>
                      ) : <span>{uoms.find(u => u.id === l.uom_id)?.uom_code || '—'}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right">
                      {canEdit ? <input type="number" value={l.unit_price} min={0} step="any" onChange={e => setLineField(l._key, 'unit_price', parseFloat(e.target.value) || 0)} className="w-24 text-right bg-transparent border-0 text-sm focus:outline-none" />
                        : <span className="text-xs font-mono tabular-nums">{fmt(l.unit_price)}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right">
                      {canEdit ? <input type="number" value={l.discount_amount} min={0} step="any" onChange={e => setLineField(l._key, 'discount_amount', parseFloat(e.target.value) || 0)} className="w-16 text-right bg-transparent border-0 text-sm focus:outline-none" />
                        : <span className="text-xs font-mono tabular-nums text-gray-500">{l.discount_amount ? fmt(l.discount_amount) : '—'}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(l.net_amount)}</td>
                    {canEdit && !fQuotation && (
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

        <div className="bg-white px-5 py-4 flex justify-end">
          <div className="w-56 divide-y divide-gray-100">
            <div className="flex items-center justify-between py-2.5">
              <span className="text-sm font-semibold text-gray-900">Total Amount</span>
              <span className="text-sm font-mono tabular-nums font-semibold text-gray-900">{fCurrency} {fmt(totalAmt)}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
