import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type DMStatus = 'draft' | 'approved' | 'paid' | 'cancelled'

type DM = {
  id: string; dm_number: string; dm_date: string; customer_id: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  source_doc_type: 'invoice' | 'receipt' | null; source_doc_id: string | null
  reason_code_id: string; remarks: string | null
  total_net_amount: number; total_vat_amount: number; total_amount: number
  status: DMStatus; posted_at: string | null; created_at: string; branch_id: string
}

type DMLLine = {
  _key: string; id?: string
  account_id: string; item_id: string; description: string
  amount: number; vat_code_id: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
  vat_amount: number; total_amount: number; line_number: number
}

type CustomerRef = { id: string; registered_name: string; tin: string; tin_branch_code: string }
type VATRef = { id: string; vat_code: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number }
type ReasonCode = { id: string; code: string; description: string }
type Branch = { id: string; branch_code: string; branch_name: string }
type COAAccount = { id: string; account_code: string; account_name: string }

// ── Helpers ──────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const newLine = (idx = 0): DMLLine => ({
  _key: crypto.randomUUID(), account_id: '', item_id: '', description: '',
  amount: 0, vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  vat_amount: 0, total_amount: 0, line_number: idx + 1,
})
const computeLine = (l: DMLLine): DMLLine => {
  const vat = l.vat_classification === 'regular' ? (l.amount * l.vat_rate) / 100 : 0
  return { ...l, vat_amount: vat, total_amount: l.amount + vat }
}

const inp = 'w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'
const ro  = 'w-full border border-gray-200 rounded px-2.5 py-1.5 text-sm bg-gray-50 text-gray-600 cursor-default'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

const statusMap: Record<DMStatus, string> = {
  draft: 'draft', approved: 'approved', paid: 'posted', cancelled: 'error',
}

export default function DebitMemosPage() {
  const { companyId, branchId } = useAppCtx()

  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [reasonCodes, setReasonCodes] = useState<ReasonCode[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [accounts, setAccounts] = useState<COAAccount[]>([])

  const [list, setList] = useState<DM[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<DMStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const PAGE = 25

  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editDoc, setEditDoc] = useState<DM | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fDate, setFDate] = useState(today())
  const [fBranch, setFBranch] = useState(branchId)
  const [fSourceType, setFSourceType] = useState<'invoice' | 'receipt' | ''>('')
  const [fReason, setFReason] = useState('')
  const [fRemarks, setFRemarks] = useState('')
  const [lines, setLines] = useState<DMLLine[]>([newLine(0)])

  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,tin,tin_branch_code')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('vat_codes').select('id,vat_code,vat_classification,tax_codes(rate)')
        .eq('transaction_type', 'output_vat').eq('is_active', true),
      supabase.from('ref_reason_codes').select('id,code,description')
        .in('applies_to', ['debit_memo', 'both']).eq('is_active', true).order('sort_order'),
      supabase.from('branches').select('id,branch_code,branch_name')
        .eq('company_id', companyId).eq('is_active', true),
      supabase.from('chart_of_accounts').select('id,account_code,account_name')
        .eq('company_id', companyId).eq('is_postable', true).eq('is_active', true).order('account_code'),
    ]).then(([{ data: cos }, { data: vcs }, { data: rcs }, { data: brs }, { data: coa }]) => {
      setCustomers(cos as CustomerRef[] || [])
      setVatCodes((vcs || []).map(v => ({
        id: v.id, vat_code: v.vat_code, vat_classification: v.vat_classification as VATRef['vat_classification'],
        rate: (Array.isArray(v.tax_codes) ? v.tax_codes[0]?.rate : (v.tax_codes as { rate?: number } | null)?.rate) ?? 0,
      })))
      setReasonCodes(rcs as ReasonCode[] || [])
      setBranches(brs as Branch[] || [])
      setAccounts(coa as COAAccount[] || [])
    })
  }, [companyId])

  const loadList = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('debit_memos').select('*', { count: 'exact' })
      .eq('company_id', companyId).order('dm_date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)
    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`dm_number.ilike.${s},customer_name_snapshot.ilike.${s}`)
    }
    const { data, count } = await q
    setList(data as DM[] || [])
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

  const setLineField = (key: string, field: keyof DMLLine, value: string | number) => {
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      if (field === 'vat_code_id') {
        const vc = vatCodes.find(v => v.id === value)
        return computeLine({ ...l, vat_code_id: value as string, vat_classification: vc?.vat_classification || 'regular', vat_rate: vc?.rate || 12 })
      }
      return computeLine({ ...l, [field]: value })
    }))
  }

  const openNew = () => {
    setEditDoc(null); setFCustomer(''); setFCustomerName(''); setFCustomerTIN('')
    setFDate(today()); setFBranch(branchId); setFSourceType(''); setFReason(''); setFRemarks('')
    setLines([newLine(0)]); setError('')
    setMode('new')
  }

  const openEdit = async (doc: DM) => {
    setEditDoc(doc)
    setFCustomer(doc.customer_id); setFCustomerName(doc.customer_name_snapshot); setFCustomerTIN(doc.customer_tin_snapshot)
    setFDate(doc.dm_date); setFBranch(doc.branch_id)
    setFSourceType((doc.source_doc_type || '') as 'invoice' | 'receipt' | '')
    setFReason(doc.reason_code_id); setFRemarks(doc.remarks || ''); setError('')
    const { data: lns } = await supabase.from('debit_memo_lines').select('*').eq('debit_memo_id', doc.id).order('line_number')
    if (lns && lns.length > 0) {
      setLines(lns.map(l => {
        const vc = vatCodes.find(v => v.id === l.vat_code_id)
        return {
          _key: l.id, id: l.id, account_id: l.account_id || '', item_id: l.item_id || '',
          description: l.description, amount: Number(l.amount), vat_code_id: l.vat_code_id || '',
          vat_classification: (vc?.vat_classification || 'regular') as DMLLine['vat_classification'],
          vat_rate: vc?.rate || 12, vat_amount: Number(l.vat_amount), total_amount: Number(l.total_amount),
          line_number: l.line_number,
        }
      }))
    } else setLines([newLine(0)])
    setMode(doc.status === 'draft' ? 'edit' : 'view')
  }

  const totalNet = lines.reduce((s, l) => s + l.amount, 0)
  const totalVAT = lines.reduce((s, l) => s + l.vat_amount, 0)
  const totalAmt = lines.reduce((s, l) => s + l.total_amount, 0)

  const save = async (nextStatus: DMStatus = 'draft') => {
    if (!companyId || !fCustomer || !fReason) { setError('Customer and Reason Code are required.'); return }
    if (lines.every(l => !l.description.trim())) { setError('At least one line is required.'); return }
    setSaving(true); setError('')
    try {
      const header = {
        company_id: companyId, branch_id: fBranch || branchId,
        customer_id: fCustomer, customer_name_snapshot: fCustomerName, customer_tin_snapshot: fCustomerTIN || '',
        source_doc_type: fSourceType || '', source_doc_id: '',
        dm_date: fDate, reason_code_id: fReason, remarks: fRemarks || '',
      }
      const linesPayload = lines
        .filter(l => l.description.trim())
        .map(l => ({
          account_id: l.account_id || '', item_id: l.item_id || '',
          description: l.description, amount: l.amount,
          vat_code_id: l.vat_code_id || '',
        }))
      const { error: rpcErr } = await supabase.rpc('fn_save_debit_memo', {
        p_dm_id: mode === 'new' ? null : (editDoc?.id ?? null),
        p_header: header,
        p_lines: linesPayload,
        p_next_status: nextStatus,
      })
      if (rpcErr) throw rpcErr
      setMode('list')
    } catch (e) { setError(e instanceof Error ? e.message : 'Save failed.') }
    setSaving(false)
  }

  const readOnly = mode === 'view'
  const canEdit = mode === 'new' || mode === 'edit'
  const dmStatus = editDoc?.status || 'draft'

  // ── List ───────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search DM#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as DMStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            {(['', 'draft', 'approved', 'paid', 'cancelled'] as const).map(s => (
              <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'All Statuses'}</option>
            ))}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={openNew}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Debit Memo
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Debit Memos.</div>
        ) : loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}
          </div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Debit Memos found</p>
            <p className="text-xs text-gray-400 mt-1">{search || filterStatus ? 'No records match the current filters.' : 'Create your first Debit Memo to get started.'}</p>
            {!search && !filterStatus && <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">New Debit Memo</button>}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['DM Date','DM Number','Customer','Source Document','Reason','Net Amount','VAT','Total','Status'].map(h => (
                    <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {list.map(dm => (
                  <tr key={dm.id} onClick={() => openEdit(dm)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                    <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={dm.dm_date} /></td>
                    <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{dm.dm_number}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{dm.customer_name_snapshot}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500">{dm.source_doc_type ? dm.source_doc_type.charAt(0).toUpperCase() + dm.source_doc_type.slice(1) : '—'}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500 max-w-[140px] truncate">{reasonCodes.find(r => r.id === dm.reason_code_id)?.description || '—'}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-600"><AmountCell amount={dm.total_net_amount} /></td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-500"><AmountCell amount={dm.total_vat_amount} /></td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={dm.total_amount} /></td>
                    <td className="px-4 py-2.5"><StatusBadge status={statusMap[dm.status]} label={dm.status.charAt(0).toUpperCase() + dm.status.slice(1)} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    )
  }

  // ── Form ───────────────────────────────────────────────────
  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <button onClick={() => setMode('list')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900">
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M15 18l-6-6 6-6" /></svg>
          Debit Memos
        </button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-mono font-semibold text-gray-900">{editDoc?.dm_number || 'New Debit Memo'}</span>
        {editDoc && <StatusBadge status={statusMap[dmStatus]} label={dmStatus.charAt(0).toUpperCase() + dmStatus.slice(1)} />}
        <div className="flex-1" />
        {error && <span className="text-xs text-red-600 font-medium">{error}</span>}
        {(mode === 'new' || dmStatus === 'draft') && !readOnly && <>
          <button onClick={() => save('draft')} disabled={saving} className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>
          <button onClick={() => save('approved')} disabled={saving} className="px-3 py-1.5 border border-blue-500 text-blue-700 rounded text-sm hover:bg-blue-50 font-medium disabled:opacity-50">Submit for Approval</button>
          <button onClick={() => save('paid')} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">Post</button>
        </>}
        {dmStatus === 'approved' && <>
          <button onClick={() => save('draft')} disabled={saving} className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">{saving ? 'Reverting…' : 'Revert to Draft'}</button>
          <button onClick={() => save('paid')} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">Post</button>
        </>}
      </div>

      <div className="divide-y divide-gray-200">
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Debit Memo Header</div>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-5 gap-y-3">
            <div><label className={lbl}>DM Number</label><div className={ro}>{editDoc?.dm_number || 'Auto-assigned on save'}</div></div>
            <div>
              <label className={lbl}>Date <span className="text-red-500">*</span></label>
              <input type="date" value={fDate} onChange={e => setFDate(e.target.value)} disabled={readOnly} className={readOnly ? ro : inp} />
            </div>
            <div>
              <label className={lbl}>Branch</label>
              <select value={fBranch} onChange={e => setFBranch(e.target.value)} disabled={readOnly} className={readOnly ? ro : inp}>
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
              <label className={lbl}>Source Document Type</label>
              {readOnly ? <div className={ro}>{fSourceType || '—'}</div> : (
                <select value={fSourceType} onChange={e => setFSourceType(e.target.value as typeof fSourceType)} className={inp}>
                  <option value="">None (standalone)</option>
                  <option value="invoice">Sales Invoice</option>
                  <option value="receipt">Receipt</option>
                </select>
              )}
            </div>
            <div>
              <label className={lbl}>Reason Code <span className="text-red-500">*</span></label>
              {readOnly ? <div className={ro}>{reasonCodes.find(r => r.id === fReason)?.description || '—'}</div> : (
                <select value={fReason} onChange={e => setFReason(e.target.value)} className={inp}>
                  <option value="">Select reason…</option>
                  {reasonCodes.map(r => <option key={r.id} value={r.id}>{r.description}</option>)}
                </select>
              )}
            </div>
            <div className="col-span-2 md:col-span-3 lg:col-span-4">
              <label className={lbl}>Remarks</label>
              {readOnly ? <div className={ro}>{fRemarks || '—'}</div> : (
                <textarea value={fRemarks} onChange={e => setFRemarks(e.target.value)} rows={2} className={inp + ' resize-none'} />
              )}
            </div>
          </div>
        </div>

        {/* Lines */}
        <div className="bg-white">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
            <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Charge Lines</span>
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
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[160px]">GL Account</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 min-w-[200px]">Description</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Amount</th>
                  <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">VAT Code</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-24">VAT</th>
                  <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-400 w-28">Total</th>
                  {canEdit && <th className="px-2 w-8" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {lines.map((l, idx) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-4 py-2.5 text-xs text-gray-400 text-right">{idx + 1}</td>
                    <td className="px-4 py-2.5">
                      {canEdit ? (
                        <select value={l.account_id} onChange={e => setLineField(l._key, 'account_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">— Select account —</option>
                          {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                        </select>
                      ) : <span className="text-xs text-gray-600">{accounts.find(a => a.id === l.account_id)?.account_name || '—'}</span>}
                    </td>
                    <td className="px-4 py-2.5">
                      {canEdit ? (
                        <input value={l.description} onChange={e => setLineField(l._key, 'description', e.target.value)}
                          className="w-full bg-transparent border-0 text-sm py-0 px-0 focus:outline-none" placeholder="Description…" />
                      ) : <span className="text-xs text-gray-700">{l.description}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right">
                      {canEdit ? (
                        <input type="number" value={l.amount} min={0} step="any"
                          onChange={e => setLineField(l._key, 'amount', parseFloat(e.target.value) || 0)}
                          className="w-24 text-right bg-transparent border-0 text-sm focus:outline-none" />
                      ) : <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(l.amount)}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-gray-500">
                      {canEdit ? (
                        <select value={l.vat_code_id} onChange={e => setLineField(l._key, 'vat_code_id', e.target.value)}
                          className="text-xs border-0 bg-transparent focus:outline-none w-full">
                          <option value="">—</option>
                          {vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}
                        </select>
                      ) : <span>{vatCodes.find(v => v.id === l.vat_code_id)?.vat_code || '—'}</span>}
                    </td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums text-gray-700">{fmt(l.vat_amount)}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(l.total_amount)}</td>
                    {canEdit && (
                      <td className="px-2 py-2.5">
                        <button type="button" onClick={() => setLines(prev => prev.filter(x => x._key !== l._key))}
                          className="text-gray-300 hover:text-red-500">
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

        {/* Summary */}
        <div className="bg-white px-5 py-4 flex justify-end">
          <div className="w-64 divide-y divide-gray-100">
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">Net Charges</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totalNet)}</span>
            </div>
            <div className="flex items-center justify-between py-1.5">
              <span className="text-xs text-gray-500">VAT</span>
              <span className="text-xs font-mono tabular-nums text-gray-700">{fmt(totalVAT)}</span>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <span className="text-sm font-semibold text-gray-900">Total Debit</span>
              <span className="text-sm font-mono tabular-nums font-semibold text-gray-900">{fmt(totalAmt)}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
