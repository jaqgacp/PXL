import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type SIStatus = 'draft' | 'approved' | 'posted' | 'cancelled'

type SI = {
  id: string; company_id: string; branch_id: string
  si_number: string; date: string; customer_id: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  customer_address_snapshot: string; payment_terms_id: string | null
  due_date: string | null; currency_code: string
  reference: string | null; memo: string | null
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_vat_amount: number
  total_amount: number; status: SIStatus
  void_reason_id: string | null; posted_at: string | null
  created_at: string; updated_at: string
}

type SILine = {
  _key: string
  id?: string
  item_id: string
  description: string
  quantity: number
  uom_id: string; uom_label: string
  unit_price: number
  discount_percent: number
  discount_amount: number
  net_amount: number
  vat_code_id: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
  vat_amount: number
  total_amount: number
  revenue_account_id: string
}

type CustomerRef = {
  id: string; registered_name: string; tin: string; tin_branch_code: string
  registered_address: string; default_tax_type: string; is_withholding_agent: boolean
  default_terms_id: string | null; default_gl_account_id: string | null
  payment_terms?: { days_to_due: number; term_name: string } | null
}

type ItemRef = {
  id: string; item_code: string; description: string
  uom_id: string; uom_label: string; standard_selling_price: number
  default_sales_vat_id: string | null; sales_account_id: string | null
}

type VATRef = {
  id: string; vat_code: string; description: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number
}

type Branch = { id: string; branch_code: string; branch_name: string }
type VoidReason = { id: string; code: string; description: string }

// ── Helpers ──────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]

const newLine = (): SILine => ({
  _key: crypto.randomUUID(),
  item_id: '', description: '', quantity: 1, uom_id: '', uom_label: '',
  unit_price: 0, discount_percent: 0, discount_amount: 0, net_amount: 0,
  vat_code_id: '', vat_classification: 'regular', vat_rate: 12, vat_amount: 0,
  total_amount: 0, revenue_account_id: '',
})

const computeLine = (l: SILine): SILine => {
  const gross = l.unit_price * l.quantity
  const disc = gross * (l.discount_percent / 100)
  const net = gross - disc
  const vat = l.vat_classification === 'regular' ? (net * l.vat_rate) / 100 : 0
  return { ...l, discount_amount: disc, net_amount: net, vat_amount: vat, total_amount: net + vat }
}

const computeTotals = (lines: SILine[]) => ({
  total_taxable_amount: lines.filter(l => l.vat_classification === 'regular').reduce((s, l) => s + l.net_amount, 0),
  total_zero_rated_amount: lines.filter(l => l.vat_classification === 'zero_rated').reduce((s, l) => s + l.net_amount, 0),
  total_exempt_amount: lines.filter(l => l.vat_classification === 'exempt').reduce((s, l) => s + l.net_amount, 0),
  total_vat_amount: lines.reduce((s, l) => s + l.vat_amount, 0),
  total_amount: lines.reduce((s, l) => s + l.total_amount, 0),
})

// ── Field style constants ────────────────────────────────────
const inp = 'w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'
const ro  = 'w-full border border-gray-200 rounded px-2.5 py-1.5 text-sm bg-gray-50 text-gray-600 cursor-default'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const celInp = 'w-full bg-transparent border-0 text-sm py-0 px-0 focus:outline-none focus:ring-0 tabular-nums'

// ── Status badge map ─────────────────────────────────────────
const statusToShared: Record<SIStatus, string> = {
  draft: 'draft', approved: 'approved', posted: 'posted', cancelled: 'error',
}

// ── Item search dropdown ──────────────────────────────────────
function ItemSearch({ items, value, onChange }: {
  items: ItemRef[]
  value: string
  onChange: (item: ItemRef) => void
}) {
  const [q, setQ] = useState('')
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const selected = items.find(i => i.id === value)

  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false) }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  const filtered = q ? items.filter(i =>
    i.item_code.toLowerCase().includes(q.toLowerCase()) ||
    i.description.toLowerCase().includes(q.toLowerCase())
  ).slice(0, 8) : items.slice(0, 8)

  return (
    <div ref={ref} className="relative">
      <input
        className={celInp + ' border-b border-gray-200'}
        value={open ? q : (selected ? `${selected.item_code} – ${selected.description}` : '')}
        placeholder="Search item…"
        onFocus={() => { setOpen(true); setQ('') }}
        onChange={e => setQ(e.target.value)}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
      />
      {open && filtered.length > 0 && (
        <div className="absolute left-0 top-full z-50 bg-white border border-gray-200 rounded shadow-lg w-72">
          {filtered.map(i => (
            <button key={i.id} type="button"
              className="w-full text-left px-3 py-2 text-xs hover:bg-blue-50 border-b border-gray-100 last:border-0"
              onMouseDown={e => { e.preventDefault(); onChange(i); setOpen(false) }}>
              <span className="font-mono font-semibold text-gray-700">{i.item_code}</span>
              <span className="ml-2 text-gray-500">{i.description}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

// ── Main ──────────────────────────────────────────────────────
export default function SalesInvoicePage() {
  const { companyId, branchId } = useAppCtx()

  // Reference data
  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [voidReasons, setVoidReasons] = useState<VoidReason[]>([])

  // List state
  const [list, setList] = useState<SI[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<SIStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const PAGE = 25
  const [page, setPage] = useState(0)

  // Form state
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editSI, setEditSI] = useState<SI | null>(null)
  const [lines, setLines] = useState<SILine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  // Form header fields
  const [fDate, setFDate] = useState(today())
  const [fBranch, setFBranch] = useState(branchId)
  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fCustomerAddr, setFCustomerAddr] = useState('')
  const [fTerms, setFTerms] = useState('')
  const [fDueDate, setFDueDate] = useState('')
  const [fCurrency, setFCurrency] = useState('PHP')
  const [fRef, setFRef] = useState('')
  const [fMemo, setFMemo] = useState('')

  // Void dialog
  const [showVoid, setShowVoid] = useState(false)
  const [voidReason, setVoidReason] = useState('')
  const [voidMemo, setVoidMemo] = useState('')

  // Load reference data
  useEffect(() => {
    if (!companyId) return
    const load = async () => {
      const [{ data: cos }, { data: itms }, { data: vcs }, { data: brs }, { data: vrs }] =
        await Promise.all([
          supabase.from('customers')
            .select('id,registered_name,tin,tin_branch_code,registered_address,default_tax_type,is_withholding_agent,default_terms_id,default_gl_account_id,payment_terms(days_to_due,term_name)')
            .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
          supabase.from('items')
            .select('id,item_code,description,uom_id,units_of_measure(uom_code),standard_selling_price,default_sales_vat_id,sales_account_id')
            .eq('company_id', companyId).eq('is_active', true).order('item_code'),
          supabase.from('vat_codes')
            .select('id,vat_code,description,vat_classification,tax_codes(rate)')
            .eq('transaction_type', 'output_vat').eq('is_active', true),
          supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true),
          supabase.from('void_reason_codes').select('id,code,description').eq('is_active', true).order('code'),
        ])

      setCustomers((cos || []).map(c => ({
        ...c,
        payment_terms: Array.isArray(c.payment_terms) ? c.payment_terms[0] : c.payment_terms,
      })) as unknown as CustomerRef[])

      setItems((itms || []).map(i => ({
        ...i,
        uom_label: (Array.isArray(i.units_of_measure)
          ? i.units_of_measure[0]?.uom_code
          : (i.units_of_measure as { uom_code?: string } | null)?.uom_code) ?? '',
      })) as unknown as ItemRef[])

      setVatCodes((vcs || []).map(v => ({
        id: v.id, vat_code: v.vat_code, description: v.description,
        vat_classification: v.vat_classification,
        rate: (Array.isArray(v.tax_codes) ? v.tax_codes[0]?.rate : (v.tax_codes as { rate?: number } | null)?.rate) ?? 0,
      })) as VATRef[])

      setBranches(brs as Branch[] || [])
      setVoidReasons(vrs as VoidReason[] || [])
    }
    load()
  }, [companyId])

  // Load list
  const loadList = useCallback(async () => {
    if (!companyId) return
    setListLoading(true)
    let q = supabase.from('sales_invoices')
      .select('*', { count: 'exact' })
      .eq('company_id', companyId)
      .order('date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)

    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`si_number.ilike.${s},customer_name_snapshot.ilike.${s},customer_tin_snapshot.ilike.${s}`)
    }

    const { data, count } = await q
    setList((data || []) as SI[])
    setTotalCount(count || 0)
    setListLoading(false)
  }, [companyId, page, filterStatus, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  // Open form
  const openNew = () => {
    setEditSI(null)
    setFDate(today()); setFBranch(branchId); setFCustomer(''); setFCustomerName('')
    setFCustomerTIN(''); setFCustomerAddr(''); setFTerms(''); setFDueDate('')
    setFCurrency('PHP'); setFRef(''); setFMemo('')
    setLines([newLine()])
    setError('')
    setMode('new')
  }

  const openEdit = async (si: SI) => {
    setEditSI(si)
    setFDate(si.date); setFBranch(si.branch_id); setFCustomer(si.customer_id)
    setFCustomerName(si.customer_name_snapshot); setFCustomerTIN(si.customer_tin_snapshot)
    setFCustomerAddr(si.customer_address_snapshot)
    setFTerms(si.payment_terms_id || ''); setFDueDate(si.due_date || '')
    setFCurrency(si.currency_code); setFRef(si.reference || ''); setFMemo(si.memo || '')
    setError('')

    // Load existing lines
    const { data: dbLines } = await supabase
      .from('sales_invoice_lines')
      .select('*')
      .eq('sales_invoice_id', si.id)
      .order('line_number')

    if (dbLines && dbLines.length > 0) {
      const mapped: SILine[] = dbLines.map(l => {
        const vc = vatCodes.find(v => v.id === l.vat_code_id)
        return {
          _key: l.id, id: l.id,
          item_id: l.item_id || '', description: l.description,
          quantity: Number(l.quantity), uom_id: l.uom_id || '', uom_label: '',
          unit_price: Number(l.unit_price), discount_percent: Number(l.discount_percent),
          discount_amount: Number(l.discount_amount), net_amount: Number(l.net_amount),
          vat_code_id: l.vat_code_id || '',
          vat_classification: (vc?.vat_classification || 'regular') as SILine['vat_classification'],
          vat_rate: vc?.rate || 12,
          vat_amount: Number(l.vat_amount), total_amount: Number(l.total_amount),
          revenue_account_id: l.revenue_account_id || '',
        }
      })
      setLines(mapped)
    } else {
      setLines([newLine()])
    }

    setMode(si.status === 'draft' || si.status === 'approved' ? 'edit' : 'view')
  }

  // Customer auto-fill
  const onCustomerChange = (id: string) => {
    const c = customers.find(x => x.id === id)
    if (!c) { setFCustomer(id); return }
    setFCustomer(id)
    setFCustomerName(c.registered_name)
    setFCustomerTIN(c.tin + (c.tin_branch_code ? `-${c.tin_branch_code}` : ''))
    setFCustomerAddr(c.registered_address)
    const pt = c.payment_terms
    if (pt && c.default_terms_id) {
      setFTerms(c.default_terms_id)
      const due = new Date(fDate)
      due.setDate(due.getDate() + pt.days_to_due)
      setFDueDate(due.toISOString().split('T')[0])
    }
  }

  // Item auto-fill per line
  const onItemChange = (key: string, item: ItemRef) => {
    const vc = vatCodes.find(v => v.id === item.default_sales_vat_id)
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      const updated: SILine = {
        ...l,
        item_id: item.id,
        description: item.description,
        uom_id: item.uom_id,
        uom_label: item.uom_label,
        unit_price: item.standard_selling_price,
        vat_code_id: vc?.id || '',
        vat_classification: vc?.vat_classification || 'regular',
        vat_rate: vc?.rate || 12,
        revenue_account_id: item.sales_account_id || '',
      }
      return computeLine(updated)
    }))
  }

  // Line field change
  const setLineField = (key: string, field: keyof SILine, value: string | number) => {
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      if (field === 'vat_code_id') {
        const vc = vatCodes.find(v => v.id === value)
        return computeLine({ ...l, vat_code_id: value as string, vat_classification: vc?.vat_classification || 'regular', vat_rate: vc?.rate || 12 })
      }
      return computeLine({ ...l, [field]: value })
    }))
  }

  // Save
  const save = async (nextStatus?: SIStatus) => {
    if (!companyId || !fCustomer || !fBranch) {
      setError('Company, Branch, and Customer are required.')
      return
    }
    if (lines.every(l => !l.description.trim())) {
      setError('At least one line item is required.')
      return
    }
    setSaving(true)
    setError('')
    try {
      const totals = computeTotals(lines)
      const isNew = mode === 'new'

      let siNumber = editSI?.si_number || ''
      if (isNew) {
        const { data: num, error: numErr } = await supabase
          .rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: fBranch, p_document_code: 'SI' })
        if (numErr || !num) throw new Error(numErr?.message || 'Could not generate SI number. Set up a Number Series for Sales Invoice in this branch.')
        siNumber = num as string
      }

      // Resolve fiscal period
      const { data: fp } = await supabase.from('fiscal_periods')
        .select('id').eq('company_id', companyId)
        .lte('start_date', fDate).gte('end_date', fDate)
        .eq('is_locked', false).maybeSingle()

      const payload = {
        company_id: companyId,
        branch_id: fBranch,
        si_number: siNumber,
        date: fDate,
        fiscal_period_id: fp?.id || null,
        customer_id: fCustomer,
        customer_name_snapshot: fCustomerName,
        customer_tin_snapshot: fCustomerTIN,
        customer_address_snapshot: fCustomerAddr,
        payment_terms_id: fTerms || null,
        due_date: fDueDate || null,
        currency_code: fCurrency,
        reference: fRef || null,
        memo: fMemo || null,
        ...totals,
        status: nextStatus || editSI?.status || 'draft',
        ...(nextStatus === 'posted' ? { posted_at: new Date().toISOString() } : {}),
      }

      let siId = editSI?.id
      if (isNew) {
        const { data: inserted, error: insertErr } = await supabase
          .from('sales_invoices').insert(payload).select('id').single()
        if (insertErr) throw insertErr
        siId = inserted.id
      } else {
        const { error: updateErr } = await supabase.from('sales_invoices')
          .update(payload).eq('id', siId!)
        if (updateErr) throw updateErr
      }

      // Upsert lines
      const validLines = lines.filter(l => l.description.trim())
      await supabase.from('sales_invoice_lines').delete().eq('sales_invoice_id', siId!)
      if (validLines.length > 0) {
        const { error: lineErr } = await supabase.from('sales_invoice_lines').insert(
          validLines.map((l, i) => ({
            sales_invoice_id: siId!,
            company_id: companyId,
            line_number: i + 1,
            item_id: l.item_id || null,
            description: l.description,
            quantity: l.quantity,
            uom_id: l.uom_id || null,
            unit_price: l.unit_price,
            discount_percent: l.discount_percent,
            discount_amount: l.discount_amount,
            net_amount: l.net_amount,
            vat_code_id: l.vat_code_id || null,
            vat_amount: l.vat_amount,
            total_amount: l.total_amount,
            revenue_account_id: l.revenue_account_id || null,
          }))
        )
        if (lineErr) throw lineErr
      }

      setMode('list')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Save failed.')
    }
    setSaving(false)
  }

  // Void
  const doVoid = async () => {
    if (!editSI || !voidReason) return
    setSaving(true)
    const { error: e } = await supabase.from('sales_invoices')
      .update({ status: 'cancelled', void_reason_id: voidReason, memo: voidMemo || editSI.memo })
      .eq('id', editSI.id)
    if (e) { setError(e.message); setSaving(false); return }
    setShowVoid(false)
    setMode('list')
    setSaving(false)
  }

  const totals = computeTotals(lines)
  const readOnly = mode === 'view'
  const canEdit = mode === 'edit' || mode === 'new'
  const siStatus = editSI?.status || 'draft'

  // ── List View ──────────────────────────────────────────────
  if (mode === 'list') {
    const filteredList = list
    const STATUS_OPTIONS: Array<SIStatus | ''> = ['', 'draft', 'approved', 'posted', 'cancelled']

    return (
      <div>
        {/* Toolbar */}
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search SI#, customer, TIN…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as SIStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'All Statuses'}</option>)}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {!companyId ? (
            <span className="text-xs text-gray-400">Select a company first</span>
          ) : (
            <button onClick={openNew}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Sales Invoice
            </button>
          )}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Sales Invoices.</div>
        ) : listLoading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(8)].map((_, i) => (
              <div key={i} className="px-5 py-3 flex gap-4 animate-pulse">
                <div className="h-3 bg-gray-100 rounded w-24" />
                <div className="h-3 bg-gray-100 rounded w-32" />
                <div className="h-3 bg-gray-100 rounded flex-1" />
                <div className="h-3 bg-gray-100 rounded w-20" />
              </div>
            ))}
          </div>
        ) : filteredList.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Sales Invoices found</p>
            <p className="text-xs text-gray-400 mt-1">
              {search || filterStatus ? 'No records match the current filters.' : 'Create your first Sales Invoice to get started.'}
            </p>
            {!search && !filterStatus && (
              <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">
                New Sales Invoice
              </button>
            )}
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['SI Number','Date','Customer','TIN','Net of VAT','VAT','Total Amount','Status'].map(h => (
                      <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {filteredList.map(si => {
                    const netOfVat = si.total_taxable_amount + si.total_zero_rated_amount + si.total_exempt_amount
                    return (
                      <tr key={si.id} onClick={() => openEdit(si)}
                        className="hover:bg-gray-50 cursor-pointer transition-colors">
                        <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{si.si_number}</td>
                        <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={si.date} /></td>
                        <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[200px] truncate">{si.customer_name_snapshot}</td>
                        <td className="px-4 py-2.5 font-mono text-xs text-gray-500 whitespace-nowrap">{si.customer_tin_snapshot}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-700"><AmountCell amount={netOfVat} /></td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-700"><AmountCell amount={si.total_vat_amount} /></td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={si.total_amount} /></td>
                        <td className="px-4 py-2.5">
                          <StatusBadge status={statusToShared[si.status]} label={si.status.charAt(0).toUpperCase() + si.status.slice(1)} />
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            {totalCount > PAGE && (
              <div className="px-5 py-2.5 border-t border-gray-200 flex items-center justify-between bg-white">
                <span className="text-xs text-gray-500">
                  Showing {page * PAGE + 1}–{Math.min((page + 1) * PAGE, totalCount)} of {totalCount}
                </span>
                <div className="flex gap-1.5">
                  <button disabled={page === 0} onClick={() => setPage(p => p - 1)}
                    className="px-2.5 py-1 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-40">← Prev</button>
                  <button disabled={(page + 1) * PAGE >= totalCount} onClick={() => setPage(p => p + 1)}
                    className="px-2.5 py-1 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-40">Next →</button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    )
  }

  // ── Form View ─────────────────────────────────────────────
  return (
    <div>
      {/* Form toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <button onClick={() => setMode('list')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900">
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M15 18l-6-6 6-6" /></svg>
          Sales Invoices
        </button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-mono font-semibold text-gray-900">
          {editSI?.si_number || 'New Sales Invoice'}
        </span>
        {editSI && (
          <StatusBadge status={statusToShared[siStatus]} label={siStatus.charAt(0).toUpperCase() + siStatus.slice(1)} />
        )}
        <div className="flex-1" />

        {error && <span className="text-xs text-red-600 font-medium">{error}</span>}

        {/* Status-based actions */}
        {(mode === 'new' || siStatus === 'draft') && !readOnly && (
          <>
            <button onClick={() => save('draft')} disabled={saving}
              className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">
              {saving ? 'Saving…' : 'Save Draft'}
            </button>
            <button onClick={() => save('approved')} disabled={saving}
              className="px-3 py-1.5 border border-blue-500 text-blue-700 rounded text-sm hover:bg-blue-50 font-medium disabled:opacity-50">
              Submit for Approval
            </button>
            <button onClick={() => save('posted')} disabled={saving}
              className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
              Post
            </button>
          </>
        )}
        {siStatus === 'approved' && !readOnly && (
          <>
            <button onClick={() => save('draft')} disabled={saving}
              className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">
              Return to Draft
            </button>
            <button onClick={() => save('posted')} disabled={saving}
              className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
              Post
            </button>
          </>
        )}
        {siStatus === 'posted' && (
          <button onClick={() => setShowVoid(true)}
            className="px-3 py-1.5 border border-red-300 text-red-700 rounded text-sm hover:bg-red-50 font-medium">
            Void
          </button>
        )}
      </div>

      <div className="divide-y divide-gray-200">

        {/* Header Section */}
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Document Header</div>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-5 gap-y-3">

            <div>
              <label className={lbl}>SI Number</label>
              <div className={ro}>{editSI?.si_number || 'Auto-assigned on save'}</div>
            </div>

            <div>
              <label className={lbl}>Date <span className="text-red-500">*</span></label>
              <input type="date" value={fDate} onChange={e => setFDate(e.target.value)}
                disabled={readOnly} className={readOnly ? ro : inp} />
            </div>

            <div>
              <label className={lbl}>Branch <span className="text-red-500">*</span></label>
              <select value={fBranch} onChange={e => setFBranch(e.target.value)}
                disabled={readOnly} className={readOnly ? ro : inp}>
                <option value="">Select branch…</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} – {b.branch_name}</option>)}
              </select>
            </div>

            <div>
              <label className={lbl}>Customer <span className="text-red-500">*</span></label>
              {readOnly ? (
                <div className={ro}>{fCustomerName}</div>
              ) : (
                <select value={fCustomer} onChange={e => onCustomerChange(e.target.value)} className={inp}>
                  <option value="">Select customer…</option>
                  {customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                </select>
              )}
            </div>

            <div>
              <label className={lbl}>Customer TIN</label>
              <div className={ro}>{fCustomerTIN || '—'}</div>
            </div>

            <div className="md:col-span-2">
              <label className={lbl}>Customer Address</label>
              {readOnly ? (
                <div className={ro}>{fCustomerAddr || '—'}</div>
              ) : (
                <input value={fCustomerAddr} onChange={e => setFCustomerAddr(e.target.value)} className={inp} />
              )}
            </div>

            <div>
              <label className={lbl}>Payment Terms</label>
              {readOnly ? (
                <div className={ro}>{customers.find(c => c.default_terms_id === fTerms)?.payment_terms?.term_name || fTerms || '—'}</div>
              ) : (
                <select value={fTerms} onChange={e => setFTerms(e.target.value)} className={inp}>
                  <option value="">Select terms…</option>
                  {customers.find(c => c.id === fCustomer)?.payment_terms && (
                    <option value={customers.find(c => c.id === fCustomer)?.default_terms_id || ''}>
                      {customers.find(c => c.id === fCustomer)?.payment_terms?.term_name}
                    </option>
                  )}
                </select>
              )}
            </div>

            <div>
              <label className={lbl}>Due Date</label>
              <div className={ro}>{fDueDate || '—'}</div>
            </div>

            <div>
              <label className={lbl}>Currency</label>
              <div className={ro}>{fCurrency}</div>
            </div>

            <div>
              <label className={lbl}>Reference</label>
              {readOnly ? (
                <div className={ro}>{fRef || '—'}</div>
              ) : (
                <input value={fRef} onChange={e => setFRef(e.target.value)} placeholder="SO#, DR#, etc." className={inp} />
              )}
            </div>

            <div className="col-span-2 md:col-span-3 lg:col-span-4">
              <label className={lbl}>Memo</label>
              {readOnly ? (
                <div className={ro}>{fMemo || '—'}</div>
              ) : (
                <textarea value={fMemo} onChange={e => setFMemo(e.target.value)}
                  rows={2} className={inp + ' resize-none'} placeholder="Prints on invoice footer…" />
              )}
            </div>

          </div>
        </div>

        {/* Lines Section */}
        <div className="bg-white">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
            <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Line Items</span>
            {canEdit && (
              <button type="button" onClick={() => setLines(prev => [...prev, newLine()])}
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
                  <th className="px-3 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-8">#</th>
                  <th className="px-3 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[180px]">Item</th>
                  <th className="px-3 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[200px]">Description</th>
                  <th className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-20">Qty</th>
                  <th className="px-3 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-16">UOM</th>
                  <th className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Unit Price</th>
                  <th className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-16">Disc%</th>
                  <th className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Net Amount</th>
                  <th className="px-3 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">VAT Code</th>
                  <th className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">VAT</th>
                  <th className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Total</th>
                  {canEdit && <th className="px-2 py-2 w-8" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {lines.map((l, idx) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-3 py-2 text-xs text-gray-400 text-right align-middle">{idx + 1}</td>
                    <td className="px-3 py-2 align-middle">
                      {canEdit ? (
                        <ItemSearch items={items} value={l.item_id}
                          onChange={item => onItemChange(l._key, item)} />
                      ) : (
                        <span className="text-xs text-gray-600">{items.find(i => i.id === l.item_id)?.item_code || '—'}</span>
                      )}
                    </td>
                    <td className="px-3 py-2 align-middle">
                      {canEdit ? (
                        <input value={l.description} onChange={e => setLineField(l._key, 'description', e.target.value)}
                          className={celInp} placeholder="Description…" />
                      ) : (
                        <span className="text-xs text-gray-700">{l.description}</span>
                      )}
                    </td>
                    <td className="px-3 py-2 align-middle text-right">
                      {canEdit ? (
                        <input type="number" value={l.quantity} min={0.0001} step="any"
                          onChange={e => setLineField(l._key, 'quantity', parseFloat(e.target.value) || 0)}
                          className={celInp + ' text-right'} />
                      ) : (
                        <span className="text-xs font-mono tabular-nums text-gray-700">{l.quantity}</span>
                      )}
                    </td>
                    <td className="px-3 py-2 align-middle text-xs text-gray-500">{l.uom_label || '—'}</td>
                    <td className="px-3 py-2 align-middle text-right">
                      {canEdit ? (
                        <input type="number" value={l.unit_price} min={0} step="any"
                          onChange={e => setLineField(l._key, 'unit_price', parseFloat(e.target.value) || 0)}
                          className={celInp + ' text-right'} />
                      ) : (
                        <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(l.unit_price)}</span>
                      )}
                    </td>
                    <td className="px-3 py-2 align-middle text-right">
                      {canEdit ? (
                        <input type="number" value={l.discount_percent} min={0} max={100} step="any"
                          onChange={e => setLineField(l._key, 'discount_percent', parseFloat(e.target.value) || 0)}
                          className={celInp + ' text-right'} />
                      ) : (
                        <span className="text-xs font-mono text-gray-500">{l.discount_percent}%</span>
                      )}
                    </td>
                    <td className="px-3 py-2 align-middle text-right font-mono text-xs tabular-nums text-gray-700">{fmt(l.net_amount)}</td>
                    <td className="px-3 py-2 align-middle">
                      {canEdit ? (
                        <select value={l.vat_code_id}
                          onChange={e => setLineField(l._key, 'vat_code_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">—</option>
                          {vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}
                        </select>
                      ) : (
                        <span className="text-xs text-gray-500">{vatCodes.find(v => v.id === l.vat_code_id)?.vat_code || '—'}</span>
                      )}
                    </td>
                    <td className="px-3 py-2 align-middle text-right font-mono text-xs tabular-nums text-gray-700">{fmt(l.vat_amount)}</td>
                    <td className="px-3 py-2 align-middle text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(l.total_amount)}</td>
                    {canEdit && (
                      <td className="px-2 py-2 align-middle">
                        <button type="button" onClick={() => setLines(prev => prev.filter(x => x._key !== l._key))}
                          className="text-gray-300 hover:text-red-500 transition-colors" title="Remove line">
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

        {/* Summary Section */}
        <div className="bg-white px-5 py-4 flex justify-end">
          <div className="w-72 divide-y divide-gray-100">
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Total Taxable Sales (VAT Base)</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totals.total_taxable_amount)}</span>
            </div>
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Total Zero-Rated Sales</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totals.total_zero_rated_amount)}</span>
            </div>
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Total Exempt Sales</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totals.total_exempt_amount)}</span>
            </div>
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Total Output VAT (12%)</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totals.total_vat_amount)}</span>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <span className="text-sm font-semibold text-gray-900">Grand Total</span>
              <span className="text-sm font-mono tabular-nums font-semibold text-gray-900">{fmt(totals.total_amount)}</span>
            </div>
          </div>
        </div>

        {/* Void footer for posted SIs */}
        {editSI?.posted_at && (
          <div className="bg-gray-50 px-5 py-3">
            <span className="text-xs text-gray-400">
              Posted {new Date(editSI.posted_at).toLocaleString('en-PH')}
              {editSI.status === 'cancelled' && ' · Voided'}
            </span>
          </div>
        )}

      </div>

      {/* Void Dialog */}
      {showVoid && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => setShowVoid(false)} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
            <h2 className="text-sm font-semibold text-gray-900 mb-1">Void Sales Invoice</h2>
            <p className="text-xs text-gray-500 mb-4">
              Voiding <span className="font-mono font-semibold">{editSI?.si_number}</span> is permanent. The SI number will not be reused per BIR regulations.
            </p>
            <div className="space-y-3">
              <div>
                <label className={lbl}>Void Reason <span className="text-red-500">*</span></label>
                <select value={voidReason} onChange={e => setVoidReason(e.target.value)} className={inp}>
                  <option value="">Select reason…</option>
                  {voidReasons.map(r => <option key={r.id} value={r.id}>{r.description}</option>)}
                </select>
              </div>
              <div>
                <label className={lbl}>Additional Notes</label>
                <textarea value={voidMemo} onChange={e => setVoidMemo(e.target.value)}
                  rows={2} className={inp + ' resize-none'} placeholder="Specify details if Other was selected…" />
              </div>
            </div>
            {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
            <div className="flex justify-end gap-2 mt-4">
              <button onClick={() => setShowVoid(false)} className="border border-gray-300 text-gray-700 px-4 py-1.5 rounded text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={doVoid} disabled={!voidReason || saving}
                className="bg-red-600 text-white px-4 py-1.5 rounded text-sm font-medium hover:bg-red-700 disabled:opacity-50">
                {saving ? 'Voiding…' : 'Void Invoice'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
