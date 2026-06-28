import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type RStatus = 'draft' | 'posted' | 'bounced' | 'cancelled'

type Receipt = {
  id: string; receipt_number: string; receipt_date: string
  customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string
  payment_mode_id: string; reference_number: string | null
  bank_account_id: string | null; total_amount: number; total_cwt: number
  remarks: string | null; status: RStatus; posted_at: string | null
  created_at: string
}

type ApplicationLine = {
  invoice_id: string; si_number: string; si_date: string
  original_amount: number; balance_due: number
  payment_amount: number; cwt_amount: number; forex_adjustment: number
  atc_code_id: string | null
}

type CustomerRef = {
  id: string; registered_name: string; tin: string; tin_branch_code: string; registered_address: string
}

type PaymentMode = { id: string; code: string; name: string }
type COAAccount  = { id: string; account_code: string; account_name: string }
type Branch      = { id: string; branch_code: string; branch_name: string }
type ATCCode     = { id: string; atc_code: string; description: string }

// ── Helpers ──────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]

const inp = 'w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'
const ro  = 'w-full border border-gray-200 rounded px-2.5 py-1.5 text-sm bg-gray-50 text-gray-600 cursor-default'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

const statusMap: Record<RStatus, string> = {
  draft: 'draft', posted: 'posted', bounced: 'error', cancelled: 'error',
}

// ── Main ──────────────────────────────────────────────────────
export default function ReceiptsPage() {
  const { companyId, branchId } = useAppCtx()

  // Reference data
  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [paymentModes, setPaymentModes] = useState<PaymentMode[]>([])
  const [bankAccounts, setBankAccounts] = useState<COAAccount[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])

  // List state
  const [list, setList] = useState<Receipt[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<RStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const PAGE = 25

  // Form state
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editDoc, setEditDoc] = useState<Receipt | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  // Form fields
  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fDate, setFDate] = useState(today())
  const [fBranch, setFBranch] = useState(branchId)
  const [fMode, setFMode] = useState('')
  const [fRef, setFRef] = useState('')
  const [fBankAccount, setFBankAccount] = useState('')
  const [fRemarks, setFRemarks] = useState('')
  const [lines, setLines] = useState<ApplicationLine[]>([])
  const [openInvoicesLoading, setOpenInvoicesLoading] = useState(false)

  // Load reference data
  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,tin,tin_branch_code,registered_address')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('ref_payment_modes').select('id,code,name').eq('is_active', true).order('sort_order'),
      supabase.from('chart_of_accounts')
        .select('id,account_code,account_name')
        .eq('company_id', companyId).eq('account_type', 'asset').eq('is_postable', true).eq('is_active', true)
        .order('account_code'),
      supabase.from('branches').select('id,branch_code,branch_name')
        .eq('company_id', companyId).eq('is_active', true),
      supabase.from('ref_atc_codes').select('id,atc_code,description').eq('is_active', true).order('atc_code'),
    ]).then(([{ data: cos }, { data: pms }, { data: coa }, { data: brs }, { data: atcs }]) => {
      setCustomers(cos as CustomerRef[] || [])
      setPaymentModes(pms as PaymentMode[] || [])
      setBankAccounts(coa as COAAccount[] || [])
      setBranches(brs as Branch[] || [])
      setAtcCodes(atcs as ATCCode[] || [])
    })
  }, [companyId])

  // Load list
  const loadList = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('receipts').select('*', { count: 'exact' })
      .eq('company_id', companyId).order('receipt_date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)
    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`receipt_number.ilike.${s},customer_name_snapshot.ilike.${s},reference_number.ilike.${s}`)
    }
    const { data, count } = await q
    setList(data as Receipt[] || [])
    setTotalCount(count || 0)
    setLoading(false)
  }, [companyId, page, filterStatus, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  // Load open invoices for customer
  const loadOpenInvoices = async (customerId: string) => {
    if (!customerId || !companyId) { setLines([]); return }
    setOpenInvoicesLoading(true)
    // Get posted SIs for customer
    const { data: sis } = await supabase.from('sales_invoices')
      .select('id,si_number,date,total_amount')
      .eq('company_id', companyId).eq('customer_id', customerId)
      .eq('status', 'posted').order('date')
    if (!sis || sis.length === 0) { setLines([]); setOpenInvoicesLoading(false); return }

    // Get all applied amounts from receipt_lines (excluding current doc if editing)
    const siIds = sis.map(s => s.id)
    const { data: applied } = await supabase.from('receipt_lines')
      .select('invoice_id,payment_amount,cwt_amount')
      .in('invoice_id', siIds)
      // Exclude current receipt if editing
      .not('receipt_id', editDoc ? 'eq' : 'is', editDoc?.id || null)

    // Also exclude credit memo applications (offset against AR)
    const { data: cmApplied } = await supabase.from('credit_memos')
      .select('invoice_id,total_amount')
      .in('invoice_id', siIds)
      .in('status', ['applied'])

    const openLines: ApplicationLine[] = sis.map(si => {
      const totalPaid = (applied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.payment_amount) + Number(a.cwt_amount), 0)
      const totalCM = (cmApplied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.total_amount), 0)
      const balance = Number(si.total_amount) - totalPaid - totalCM
      return {
        invoice_id: si.id, si_number: si.si_number, si_date: si.date,
        original_amount: Number(si.total_amount), balance_due: balance,
        payment_amount: 0, cwt_amount: 0, forex_adjustment: 0, atc_code_id: null,
      }
    }).filter(l => l.balance_due > 0.005)

    setLines(openLines)
    setOpenInvoicesLoading(false)
  }

  // Customer auto-fill
  const onCustomerChange = (id: string) => {
    const c = customers.find(x => x.id === id)
    setFCustomer(id)
    setFCustomerName(c?.registered_name || '')
    setFCustomerTIN(c ? c.tin + (c.tin_branch_code !== '000' ? `-${c.tin_branch_code}` : '') : '')
    loadOpenInvoices(id)
  }

  // Open form
  const openNew = () => {
    setEditDoc(null)
    setFCustomer(''); setFCustomerName(''); setFCustomerTIN('')
    setFDate(today()); setFBranch(branchId)
    setFMode(''); setFRef(''); setFBankAccount(''); setFRemarks('')
    setLines([]); setError('')
    setMode('new')
  }

  const openEdit = async (doc: Receipt) => {
    setEditDoc(doc)
    setFCustomer(doc.customer_id); setFCustomerName(doc.customer_name_snapshot)
    setFCustomerTIN(doc.customer_tin_snapshot)
    setFDate(doc.receipt_date); setFBranch(doc.id) // branch not stored separately
    setFMode(doc.payment_mode_id); setFRef(doc.reference_number || '')
    setFBankAccount(doc.bank_account_id || ''); setFRemarks(doc.remarks || '')
    setError('')

    // Load existing applied lines
    const { data: rl } = await supabase.from('receipt_lines')
      .select('*').eq('receipt_id', doc.id)
    const { data: siData } = rl?.length
      ? await supabase.from('sales_invoices').select('id,si_number,date,total_amount')
          .in('id', rl.map(r => r.invoice_id))
      : { data: [] }

    const mapped: ApplicationLine[] = (rl || []).map(r => {
      const si = (siData || []).find(s => s.id === r.invoice_id)
      return {
        invoice_id: r.invoice_id, si_number: si?.si_number || '—',
        si_date: si?.date || '', original_amount: Number(si?.total_amount || 0),
        balance_due: 0, // will be stale, but fine for view
        payment_amount: Number(r.payment_amount), cwt_amount: Number(r.cwt_amount),
        forex_adjustment: Number(r.forex_adjustment), atc_code_id: r.atc_code_id || null,
      }
    })
    setLines(mapped)
    setMode(doc.status === 'draft' ? 'edit' : 'view')
  }

  const setLineField = (invoiceId: string, field: 'payment_amount' | 'cwt_amount' | 'forex_adjustment', val: number) => {
    setLines(prev => prev.map(l => l.invoice_id === invoiceId ? { ...l, [field]: val } : l))
  }

  const setLineAtc = (invoiceId: string, atcCodeId: string | null) => {
    setLines(prev => prev.map(l => l.invoice_id === invoiceId ? { ...l, atc_code_id: atcCodeId } : l))
  }

  const totalPayment = lines.reduce((s, l) => s + l.payment_amount, 0)
  const totalCWT = lines.reduce((s, l) => s + l.cwt_amount, 0)
  const appliedLines = lines.filter(l => l.payment_amount > 0 || l.cwt_amount > 0)

  const save = async (nextStatus: RStatus = 'draft') => {
    if (!companyId || !fCustomer || !fMode) {
      setError('Customer and Payment Mode are required.')
      return
    }
    if (appliedLines.length === 0) {
      setError('At least one invoice must have a payment amount.')
      return
    }
    setSaving(true); setError('')
    try {
      const isNew = mode === 'new'
      let receiptNum = editDoc?.receipt_number || ''
      if (isNew) {
        const { data: num, error: numErr } = await supabase.rpc('fn_next_document_number', {
          p_company_id: companyId, p_branch_id: fBranch || branchId, p_document_code: 'OR',
        })
        if (numErr || !num) throw new Error(numErr?.message || 'No number series for Official Receipts. Set one up in Number Series Setup.')
        receiptNum = num as string
      }

      const payload = {
        company_id: companyId,
        branch_id: fBranch || branchId,
        customer_id: fCustomer,
        customer_name_snapshot: fCustomerName,
        customer_tin_snapshot: fCustomerTIN,
        receipt_number: receiptNum,
        receipt_date: fDate,
        payment_mode_id: fMode,
        reference_number: fRef || null,
        bank_account_id: fBankAccount || null,
        total_amount: totalPayment,
        total_cwt: totalCWT,
        remarks: fRemarks || null,
        status: nextStatus,
        ...(nextStatus === 'posted' ? { posted_at: new Date().toISOString() } : {}),
      }

      let docId = editDoc?.id
      if (isNew) {
        const { data: ins, error: ie } = await supabase.from('receipts').insert(payload).select('id').single()
        if (ie) throw ie
        docId = ins.id
      } else {
        const { error: ue } = await supabase.from('receipts').update(payload).eq('id', docId!)
        if (ue) throw ue
      }

      await supabase.from('receipt_lines').delete().eq('receipt_id', docId!)
      if (appliedLines.length > 0) {
        const { error: le } = await supabase.from('receipt_lines').insert(
          appliedLines.map(l => ({
            receipt_id: docId!, company_id: companyId,
            invoice_id: l.invoice_id, payment_amount: l.payment_amount,
            cwt_amount: l.cwt_amount, forex_adjustment: l.forex_adjustment,
            atc_code_id: l.cwt_amount > 0 ? l.atc_code_id : null,
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

  // ── List View ─────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search receipt#, customer, reference…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as RStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            {(['', 'draft', 'posted', 'bounced', 'cancelled'] as const).map(s => (
              <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'All Statuses'}</option>
            ))}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={openNew}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              Receive Payment
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Receipts.</div>
        ) : loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(8)].map((_, i) => (
              <div key={i} className="px-5 py-3 flex gap-4 animate-pulse">
                <div className="h-3 bg-gray-100 rounded w-24" />
                <div className="h-3 bg-gray-100 rounded flex-1" />
                <div className="h-3 bg-gray-100 rounded w-20" />
              </div>
            ))}
          </div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Receipts found</p>
            <p className="text-xs text-gray-400 mt-1">
              {search || filterStatus ? 'No records match the current filters.' : 'Record your first customer payment to get started.'}
            </p>
            {!search && !filterStatus && (
              <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">
                Receive Payment
              </button>
            )}
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Receipt Date','Receipt Number','Customer','TIN','Payment Mode','Amount','CWT','Status'].map(h => (
                      <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {list.map(r => {
                    const pm = paymentModes.find(p => p.id === r.payment_mode_id)
                    return (
                      <tr key={r.id} onClick={() => openEdit(r)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                        <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={r.receipt_date} /></td>
                        <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{r.receipt_number}</td>
                        <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[200px] truncate">{r.customer_name_snapshot}</td>
                        <td className="px-4 py-2.5 font-mono text-xs text-gray-500 whitespace-nowrap">{r.customer_tin_snapshot}</td>
                        <td className="px-4 py-2.5 text-xs text-gray-600">{pm?.name || '—'}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={r.total_amount} /></td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-500"><AmountCell amount={r.total_cwt} /></td>
                        <td className="px-4 py-2.5">
                          <StatusBadge status={statusMap[r.status]} label={r.status.charAt(0).toUpperCase() + r.status.slice(1)} />
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
            {totalCount > PAGE && (
              <div className="px-5 py-2.5 border-t border-gray-200 flex items-center justify-between bg-white">
                <span className="text-xs text-gray-500">Showing {page * PAGE + 1}–{Math.min((page + 1) * PAGE, totalCount)} of {totalCount}</span>
                <div className="flex gap-1.5">
                  <button disabled={page === 0} onClick={() => setPage(p => p - 1)} className="px-2.5 py-1 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-40">← Prev</button>
                  <button disabled={(page + 1) * PAGE >= totalCount} onClick={() => setPage(p => p + 1)} className="px-2.5 py-1 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-40">Next →</button>
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
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <button onClick={() => setMode('list')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900">
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M15 18l-6-6 6-6" /></svg>
          Receipts
        </button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-mono font-semibold text-gray-900">{editDoc?.receipt_number || 'New Receipt'}</span>
        {editDoc && <StatusBadge status={statusMap[editDoc.status]} label={editDoc.status.charAt(0).toUpperCase() + editDoc.status.slice(1)} />}
        <div className="flex-1" />
        {error && <span className="text-xs text-red-600 font-medium">{error}</span>}
        {canEdit && <>
          <button onClick={() => save('draft')} disabled={saving}
            className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">
            {saving ? 'Saving…' : 'Save Draft'}
          </button>
          <button onClick={() => save('posted')} disabled={saving}
            className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            Post Receipt
          </button>
        </>}
        {editDoc?.status === 'posted' && (
          <button onClick={() => save('bounced')} disabled={saving}
            className="px-3 py-1.5 border border-red-300 text-red-700 rounded text-sm hover:bg-red-50 font-medium">
            Mark Bounced
          </button>
        )}
      </div>

      <div className="divide-y divide-gray-200">
        {/* Header */}
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Receipt Header</div>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-5 gap-y-3">
            <div>
              <label className={lbl}>Receipt Number</label>
              <div className={ro}>{editDoc?.receipt_number || 'Auto-assigned on save'}</div>
            </div>
            <div>
              <label className={lbl}>Date <span className="text-red-500">*</span></label>
              <input type="date" value={fDate} onChange={e => setFDate(e.target.value)}
                disabled={readOnly} className={readOnly ? ro : inp} />
            </div>
            <div>
              <label className={lbl}>Branch</label>
              <select value={fBranch} onChange={e => setFBranch(e.target.value)}
                disabled={readOnly} className={readOnly ? ro : inp}>
                <option value="">Select branch…</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} – {b.branch_name}</option>)}
              </select>
            </div>
            <div>
              <label className={lbl}>Customer <span className="text-red-500">*</span></label>
              {readOnly ? <div className={ro}>{fCustomerName}</div> : (
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
            <div>
              <label className={lbl}>Payment Mode <span className="text-red-500">*</span></label>
              {readOnly ? (
                <div className={ro}>{paymentModes.find(p => p.id === fMode)?.name || '—'}</div>
              ) : (
                <select value={fMode} onChange={e => setFMode(e.target.value)} className={inp}>
                  <option value="">Select mode…</option>
                  {paymentModes.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              )}
            </div>
            <div>
              <label className={lbl}>Reference No. (Check / Bank Trace)</label>
              {readOnly ? <div className={ro}>{fRef || '—'}</div> : (
                <input value={fRef} onChange={e => setFRef(e.target.value)} className={inp} placeholder="Check number or bank trace…" />
              )}
            </div>
            <div>
              <label className={lbl}>Deposit to Account</label>
              {readOnly ? (
                <div className={ro}>{bankAccounts.find(a => a.id === fBankAccount)?.account_name || '—'}</div>
              ) : (
                <select value={fBankAccount} onChange={e => setFBankAccount(e.target.value)} className={inp}>
                  <option value="">Select account…</option>
                  {bankAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code} – {a.account_name}</option>)}
                </select>
              )}
            </div>
            <div className="col-span-2 md:col-span-3 lg:col-span-4">
              <label className={lbl}>Remarks</label>
              {readOnly ? <div className={ro}>{fRemarks || '—'}</div> : (
                <textarea value={fRemarks} onChange={e => setFRemarks(e.target.value)}
                  rows={2} className={inp + ' resize-none'} />
              )}
            </div>
          </div>
        </div>

        {/* Invoice Application Table */}
        <div className="bg-white">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
            <div>
              <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Invoice Application</span>
              {fCustomer && !readOnly && (
                <span className="ml-3 text-xs text-gray-400">
                  {openInvoicesLoading ? 'Loading open invoices…' :
                    lines.length === 0 ? 'No open invoices for this customer' :
                    `${lines.length} open invoice${lines.length !== 1 ? 's' : ''}`}
                </span>
              )}
            </div>
            {!fCustomer && !readOnly && (
              <span className="text-xs text-gray-400">Select a customer to see open invoices</span>
            )}
          </div>

          {lines.length === 0 && !openInvoicesLoading ? (
            <div className="py-10 text-center text-sm text-gray-400">
              {fCustomer ? 'No open invoices found for this customer.' : 'Select a customer above to load open invoices.'}
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['SI Number','SI Date','Original Amount','Balance Due','Payment Amount','CWT (2307)','ATC Code','Forex Adj.','Remaining After'].map(h => (
                      <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap last:text-right">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {lines.map(l => {
                    const remaining = l.balance_due - l.payment_amount - l.cwt_amount - l.forex_adjustment
                    const isOver = l.payment_amount + l.cwt_amount > l.balance_due + 0.005
                    return (
                      <tr key={l.invoice_id} className={`hover:bg-gray-50 ${isOver ? 'bg-red-50/30' : ''}`}>
                        <td className="px-4 py-2.5 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">{l.si_number}</td>
                        <td className="px-4 py-2.5 text-xs text-gray-500 whitespace-nowrap"><DateCell date={l.si_date} /></td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums text-gray-600">{fmt(l.original_amount)}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(l.balance_due)}</td>
                        <td className="px-4 py-2.5">
                          {readOnly ? (
                            <span className="font-mono text-xs tabular-nums text-gray-700">{fmt(l.payment_amount)}</span>
                          ) : (
                            <input type="number" min={0} step="any"
                              value={l.payment_amount || ''}
                              onChange={e => setLineField(l.invoice_id, 'payment_amount', parseFloat(e.target.value) || 0)}
                              className="w-28 border border-gray-300 rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900"
                              placeholder="0.00" />
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {readOnly ? (
                            <span className="font-mono text-xs tabular-nums text-gray-500">{fmt(l.cwt_amount)}</span>
                          ) : (
                            <input type="number" min={0} step="any"
                              value={l.cwt_amount || ''}
                              onChange={e => setLineField(l.invoice_id, 'cwt_amount', parseFloat(e.target.value) || 0)}
                              className="w-24 border border-gray-300 rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900"
                              placeholder="0.00" />
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {l.cwt_amount > 0 ? (
                            readOnly ? (
                              <span className="font-mono text-xs text-gray-600">
                                {atcCodes.find(a => a.id === l.atc_code_id)?.atc_code || '—'}
                              </span>
                            ) : (
                              <select
                                value={l.atc_code_id || ''}
                                onChange={e => setLineAtc(l.invoice_id, e.target.value || null)}
                                className="w-28 border border-gray-300 rounded px-1.5 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                                <option value="">Select…</option>
                                {atcCodes.map(a => (
                                  <option key={a.id} value={a.id}>{a.atc_code}</option>
                                ))}
                              </select>
                            )
                          ) : (
                            <span className="text-xs text-gray-300">—</span>
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {readOnly ? (
                            <span className="font-mono text-xs tabular-nums text-gray-500">{fmt(l.forex_adjustment)}</span>
                          ) : (
                            <input type="number" step="any"
                              value={l.forex_adjustment || ''}
                              onChange={e => setLineField(l.invoice_id, 'forex_adjustment', parseFloat(e.target.value) || 0)}
                              className="w-24 border border-gray-300 rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900"
                              placeholder="0.00" />
                          )}
                        </td>
                        <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums ${remaining < -0.005 ? 'text-red-700 font-semibold' : 'text-gray-600'}`}>
                          {fmt(Math.max(0, remaining))}
                          {isOver && <span className="ml-1 text-red-500 text-[10px]">Exceeds balance</span>}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Summary */}
        <div className="bg-white px-5 py-4 flex justify-end">
          <div className="w-64 divide-y divide-gray-100">
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Total Payment Applied</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totalPayment)}</span>
            </div>
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Total CWT (2307) Applied</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totalCWT)}</span>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <span className="text-sm font-semibold text-gray-900">Total Collected</span>
              <span className="text-sm font-mono tabular-nums font-semibold text-gray-900">{fmt(totalPayment + totalCWT)}</span>
            </div>
          </div>
        </div>

        {editDoc?.posted_at && (
          <div className="bg-gray-50 px-5 py-3">
            <span className="text-xs text-gray-400">Posted {new Date(editDoc.posted_at).toLocaleString('en-PH')}</span>
          </div>
        )}
      </div>
    </div>
  )
}
