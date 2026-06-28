import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type QStatus = 'draft' | 'pending' | 'approved' | 'rejected' | 'expired'

type Quotation = {
  id: string; quotation_number: string; quotation_date: string; validity_date: string
  customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string
  currency_code: string; reference_number: string | null; remarks: string | null
  total_amount: number; status: QStatus; branch_id: string; created_at: string
}

type QLine = {
  _key: string; id?: string; line_number: number
  item_id: string; description: string
  quantity: number; uom_id: string; unit_price: number
  discount_amount: number; net_amount: number
}

type CustomerRef = { id: string; registered_name: string; tin: string; tin_branch_code: string; payment_terms_id: string | null }
type ItemRef = { id: string; item_code: string; item_name: string; default_uom_id: string | null; default_sales_price: number | null }
type UOMRef = { id: string; uom_code: string; uom_name: string }
type Branch = { id: string; branch_code: string; branch_name: string }

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const addDays = (d: string, n: number) => {
  const dt = new Date(d); dt.setDate(dt.getDate() + n); return dt.toISOString().split('T')[0]
}
const newLine = (idx = 0): QLine => ({
  _key: crypto.randomUUID(), line_number: idx + 1,
  item_id: '', description: '', quantity: 1, uom_id: '', unit_price: 0, discount_amount: 0, net_amount: 0,
})
const computeNet = (l: QLine): QLine => ({
  ...l, net_amount: Math.max(0, l.quantity * l.unit_price - l.discount_amount),
})

const inp = 'w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'
const ro  = 'w-full border border-gray-200 rounded px-2.5 py-1.5 text-sm bg-gray-50 text-gray-600 cursor-default'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

const QstatusMap: Record<QStatus, string> = {
  draft: 'draft', pending: 'draft', approved: 'approved', rejected: 'error', expired: 'warning',
}

export default function QuotationsPage() {
  const { companyId, branchId } = useAppCtx()

  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [uoms, setUOMs] = useState<UOMRef[]>([])
  const [branches, setBranches] = useState<Branch[]>([])

  const [list, setList] = useState<Quotation[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<QStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const PAGE = 25

  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editDoc, setEditDoc] = useState<Quotation | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fDate, setFDate] = useState(today())
  const [fValidity, setFValidity] = useState(addDays(today(), 30))
  const [fBranch, setFBranch] = useState(branchId)
  const [fCurrency, setFCurrency] = useState('PHP')
  const [fRef, setFRef] = useState('')
  const [fRemarks, setFRemarks] = useState('')
  const [lines, setLines] = useState<QLine[]>([newLine(0)])

  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,tin,tin_branch_code,payment_terms_id')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('items').select('id,item_code,item_name,default_uom_id,default_sales_price')
        .eq('company_id', companyId).eq('is_active', true).order('item_name'),
      supabase.from('units_of_measure').select('id,uom_code,uom_name').eq('is_active', true).order('uom_name'),
      supabase.from('branches').select('id,branch_code,branch_name')
        .eq('company_id', companyId).eq('is_active', true),
    ]).then(([{ data: cs }, { data: is }, { data: us }, { data: bs }]) => {
      setCustomers(cs as CustomerRef[] || [])
      setItems(is as ItemRef[] || [])
      setUOMs(us as UOMRef[] || [])
      setBranches(bs as Branch[] || [])
    })
  }, [companyId])

  const loadList = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('sales_quotations').select('*', { count: 'exact' })
      .eq('company_id', companyId).order('quotation_date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)
    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`quotation_number.ilike.${s},customer_name_snapshot.ilike.${s}`)
    }
    const { data, count } = await q
    setList(data as Quotation[] || [])
    setTotalCount(count || 0)
    setLoading(false)
  }, [companyId, page, filterStatus, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  const onCustomerChange = (id: string) => {
    const c = customers.find(x => x.id === id)
    setFCustomer(id)
    setFCustomerName(c?.registered_name || '')
    setFCustomerTIN(c ? c.tin + (c.tin_branch_code !== '000' ? `-${c.tin_branch_code}` : '') : '')
  }

  const setLineField = (key: string, field: keyof QLine, value: string | number) => {
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
    setEditDoc(null); setFCustomer(''); setFCustomerName(''); setFCustomerTIN('')
    setFDate(today()); setFValidity(addDays(today(), 30)); setFBranch(branchId)
    setFCurrency('PHP'); setFRef(''); setFRemarks(''); setLines([newLine(0)]); setError('')
    setMode('new')
  }

  const openEdit = async (doc: Quotation) => {
    setEditDoc(doc)
    setFCustomer(doc.customer_id); setFCustomerName(doc.customer_name_snapshot); setFCustomerTIN(doc.customer_tin_snapshot)
    setFDate(doc.quotation_date); setFValidity(doc.validity_date); setFBranch(doc.branch_id)
    setFCurrency(doc.currency_code); setFRef(doc.reference_number || ''); setFRemarks(doc.remarks || ''); setError('')
    const { data: lns } = await supabase.from('sales_quotation_lines').select('*').eq('quotation_id', doc.id).order('line_number')
    if (lns && lns.length) setLines(lns.map(l => ({ _key: l.id, id: l.id, line_number: l.line_number, item_id: l.item_id || '', description: l.description, quantity: Number(l.quantity), uom_id: l.uom_id || '', unit_price: Number(l.unit_price), discount_amount: Number(l.discount_amount), net_amount: Number(l.net_amount) })))
    else setLines([newLine(0)])
    setMode(doc.status === 'draft' || doc.status === 'pending' ? 'edit' : 'view')
  }

  const totalAmt = lines.reduce((s, l) => s + l.net_amount, 0)

  const save = async (nextStatus: QStatus) => {
    if (!companyId || !fCustomer) { setError('Customer is required.'); return }
    if (lines.every(l => !l.description.trim())) { setError('At least one line item is required.'); return }
    setSaving(true); setError('')
    try {
      const isNew = mode === 'new'
      let docNum = editDoc?.quotation_number || ''
      if (isNew) {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', {
          p_company_id: companyId, p_branch_id: fBranch || branchId, p_document_code: 'QT',
        })
        if (ne || !num) throw new Error(ne?.message || 'No number series for Quotations (code: QT). Configure in Number Series setup.')
        docNum = num as string
      }
      const payload = {
        company_id: companyId, branch_id: fBranch || branchId,
        customer_id: fCustomer, customer_name_snapshot: fCustomerName, customer_tin_snapshot: fCustomerTIN,
        quotation_number: docNum, quotation_date: fDate, validity_date: fValidity,
        currency_code: fCurrency, reference_number: fRef || null, remarks: fRemarks || null,
        total_amount: totalAmt, status: nextStatus,
      }
      let docId = editDoc?.id
      if (isNew) {
        const { data: ins, error: ie } = await supabase.from('sales_quotations').insert(payload).select('id').single()
        if (ie) throw ie; docId = ins.id
      } else {
        const { error: ue } = await supabase.from('sales_quotations').update(payload).eq('id', docId!)
        if (ue) throw ue
      }
      const validLines = lines.filter(l => l.description.trim())
      await supabase.from('sales_quotation_lines').delete().eq('quotation_id', docId!)
      if (validLines.length) {
        const { error: le } = await supabase.from('sales_quotation_lines').insert(
          validLines.map((l, i) => ({
            quotation_id: docId!, company_id: companyId, line_number: i + 1,
            item_id: l.item_id || null, description: l.description, quantity: l.quantity,
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
  const qStatus = editDoc?.status || 'draft'

  // ── List ────────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search QT#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as QStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            <option value="">All Statuses</option>
            {(['draft','pending','approved','rejected','expired'] as QStatus[]).map(s => (
              <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
            ))}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={openNew} className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Quotation
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Quotations.</div>
        ) : loading ? (
          <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Quotations found</p>
            <p className="text-xs text-gray-400 mt-1">{search || filterStatus ? 'No records match the current filters.' : 'Create your first Quotation to start the sales pipeline.'}</p>
            {!search && !filterStatus && <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">New Quotation</button>}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['QT Date','QT Number','Customer','Validity Date','Ref No.','Currency','Total Amount','Status'].map(h => (
                    <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {list.map(q => (
                  <tr key={q.id} onClick={() => openEdit(q)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                    <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={q.quotation_date} /></td>
                    <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{q.quotation_number}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{q.customer_name_snapshot}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500 whitespace-nowrap"><DateCell date={q.validity_date} /></td>
                    <td className="px-4 py-2.5 text-xs text-gray-400">{q.reference_number || '—'}</td>
                    <td className="px-4 py-2.5 text-xs font-mono text-gray-500">{q.currency_code}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={q.total_amount} /></td>
                    <td className="px-4 py-2.5"><StatusBadge status={QstatusMap[q.status]} label={q.status.charAt(0).toUpperCase() + q.status.slice(1)} /></td>
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
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <button onClick={() => setMode('list')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900">
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M15 18l-6-6 6-6" /></svg>
          Quotations
        </button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-mono font-semibold text-gray-900">{editDoc?.quotation_number || 'New Quotation'}</span>
        {editDoc && <StatusBadge status={QstatusMap[qStatus]} label={qStatus.charAt(0).toUpperCase() + qStatus.slice(1)} />}
        <div className="flex-1" />
        {error && <span className="text-xs text-red-600 font-medium max-w-xs text-right">{error}</span>}
        {(mode === 'new' || qStatus === 'draft') && !readOnly && <>
          <button onClick={() => save('draft')} disabled={saving} className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>
          <button onClick={() => save('pending')} disabled={saving} className="px-3 py-1.5 border border-blue-500 text-blue-700 rounded text-sm hover:bg-blue-50 font-medium disabled:opacity-50">Submit for Approval</button>
        </>}
        {qStatus === 'pending' && !readOnly && <>
          <button onClick={() => save('draft')} disabled={saving} className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">Return to Draft</button>
          <button onClick={() => save('rejected')} disabled={saving} className="px-3 py-1.5 border border-red-300 text-red-600 rounded text-sm hover:bg-red-50 disabled:opacity-50">Reject</button>
          <button onClick={() => save('approved')} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">Approve</button>
        </>}
      </div>

      <div className="divide-y divide-gray-200">
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Quotation Header</div>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-5 gap-y-3">
            <div><label className={lbl}>QT Number</label><div className={ro}>{editDoc?.quotation_number || 'Auto-assigned on save'}</div></div>
            <div>
              <label className={lbl}>Quotation Date <span className="text-red-500">*</span></label>
              <input type="date" value={fDate} onChange={e => setFDate(e.target.value)} disabled={readOnly} className={readOnly ? ro : inp} />
            </div>
            <div>
              <label className={lbl}>Validity Date <span className="text-red-500">*</span></label>
              <input type="date" value={fValidity} onChange={e => setFValidity(e.target.value)} disabled={readOnly} className={readOnly ? ro : inp} />
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
            <div className="col-span-2">
              <label className={lbl}>Customer <span className="text-red-500">*</span></label>
              {readOnly ? <div className={ro}>{fCustomerName}</div> : (
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
              {readOnly ? <div className={ro}>{fRef || '—'}</div> : <input value={fRef} onChange={e => setFRef(e.target.value)} placeholder="Customer RFQ / PO reference" className={inp} />}
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
            {canEdit && (
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
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">Qty</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-20">UOM</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Unit Price</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">Discount</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Net Amount</th>
                  {canEdit && <th className="px-2 w-8" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {lines.map((l, idx) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-4 py-2.5 text-xs text-gray-400 text-right">{idx + 1}</td>
                    <td className="px-4 py-2.5">
                      {canEdit ? (
                        <select value={l.item_id} onChange={e => setLineField(l._key, 'item_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">— Select item —</option>
                          {items.map(i => <option key={i.id} value={i.id}>{i.item_code} — {i.item_name}</option>)}
                        </select>
                      ) : <span className="text-xs text-gray-600">{items.find(i => i.id === l.item_id)?.item_name || '—'}</span>}
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
                      {canEdit ? (
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
                      {canEdit ? <input type="number" value={l.discount_amount} min={0} step="any" onChange={e => setLineField(l._key, 'discount_amount', parseFloat(e.target.value) || 0)} className="w-20 text-right bg-transparent border-0 text-sm focus:outline-none" />
                        : <span className="text-xs font-mono tabular-nums text-gray-500">{l.discount_amount ? fmt(l.discount_amount) : '—'}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(l.net_amount)}</td>
                    {canEdit && (
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
