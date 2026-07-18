import { useState, useEffect, useCallback, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'
import { composePhTin } from '@/lib/philippines'

// ── Types ─────────────────────────────────────────────────────
type CMStatus = 'draft' | 'approved' | 'applied' | 'cancelled'

type CM = {
  id: string; cm_number: string; cm_date: string; customer_id: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  invoice_id: string | null; reason_code_id: string; remarks: string | null
  total_net_amount: number; total_vat_amount: number; total_amount: number
  status: CMStatus; posted_at: string | null; created_at: string; updated_at: string; branch_id: string
}

type CMLLine = {
  _key: string; id?: string
  invoice_line_id: string; item_id: string; description: string
  quantity: number; unit_price: number; net_amount: number
  vat_code_id: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
  vat_amount: number; total_amount: number; revenue_account_id: string
}

type CustomerRef = { id: string; registered_name: string; tin: string; tin_branch_code: string }
type SIRef = { id: string; si_number: string; date: string; total_amount: number }
type SILine = {
  id: string; description: string; quantity: number; unit_price: number; net_amount: number
  vat_code_id: string | null; vat_amount: number; total_amount: number
  revenue_account_id: string | null; item_id: string | null
}
type VATRef = { id: string; vat_code: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number }
type ReasonCode = { id: string; code: string; description: string }
type Branch = { id: string; branch_code: string; branch_name: string }

// ── Helpers ──────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
const newLine = (): CMLLine => ({
  _key: crypto.randomUUID(), description: '', quantity: 1, unit_price: 0,
  net_amount: 0, vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  vat_amount: 0, total_amount: 0, revenue_account_id: '', item_id: '',
  invoice_line_id: '',
})
const computeLine = (l: CMLLine): CMLLine => {
  const net = l.unit_price * l.quantity
  const vat = l.vat_classification === 'regular' ? (net * l.vat_rate) / 100 : 0
  return { ...l, net_amount: net, vat_amount: vat, total_amount: net + vat }
}

const inp = 'w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'
const ro  = 'w-full border border-gray-200 rounded px-2.5 py-1.5 text-sm bg-gray-50 text-gray-600 cursor-default'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

const statusMap: Record<CMStatus, string> = {
  draft: 'draft', approved: 'approved', applied: 'posted', cancelled: 'error',
}

export default function CreditMemosPage() {
  const { companyId, branchId } = useAppCtx()

  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [reasonCodes, setReasonCodes] = useState<ReasonCode[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [openSIs, setOpenSIs] = useState<SIRef[]>([])
  const [siLines, setSiLines] = useState<SILine[]>([])

  const [list, setList] = useState<CM[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<CMStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const PAGE = 25

  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editDoc, setEditDoc] = useState<CM | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fDate, setFDate] = useState(today())
  const [fBranch, setFBranch] = useState(branchId)
  const [fInvoice, setFInvoice] = useState('')
  const [fReason, setFReason] = useState('')
  const [fRemarks, setFRemarks] = useState('')
  const [lines, setLines] = useState<CMLLine[]>([newLine()])

  // Load reference data
  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('companies').select('tax_registration').eq('id', companyId).single(),
      supabase.from('customers').select('id,registered_name,tin,tin_branch_code')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('vat_codes').select('id,vat_code,vat_classification,tax_codes(rate)')
        .eq('transaction_type', 'output_vat').eq('is_active', true),
      supabase.from('ref_reason_codes').select('id,code,description')
        .in('applies_to', ['credit_memo', 'both']).eq('is_active', true).order('sort_order'),
      supabase.from('branches').select('id,branch_code,branch_name')
        .eq('company_id', companyId).eq('is_active', true),
    ]).then(([{ data: company }, { data: cos }, { data: vcs }, { data: rcs }, { data: brs }]) => {
      const taxRegistration = company?.tax_registration || 'vat'
      setCustomers(cos as CustomerRef[] || [])
      setVatCodes((vcs || []).map(v => ({
        id: v.id, vat_code: v.vat_code, vat_classification: v.vat_classification as VATRef['vat_classification'],
        rate: (Array.isArray(v.tax_codes) ? v.tax_codes[0]?.rate : (v.tax_codes as { rate?: number } | null)?.rate) ?? 0,
      })).filter(v => taxRegistration === 'vat' || v.rate === 0))
      setReasonCodes(rcs as ReasonCode[] || [])
      setBranches(brs as Branch[] || [])
    })
  }, [companyId])

  const loadList = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('credit_memos').select('*', { count: 'exact' })
      .eq('company_id', companyId).order('cm_date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)
    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      q = q.or(`cm_number.ilike.${s},customer_name_snapshot.ilike.${s}`)
    }
    const { data, count } = await q
    setList(data as CM[] || [])
    setTotalCount(count || 0)
    setLoading(false)
  }, [companyId, page, filterStatus, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  const onCustomerChange = async (id: string) => {
    const c = customers.find(x => x.id === id)
    setFCustomer(id)
    setFCustomerName(c?.registered_name || '')
    setFCustomerTIN(c ? composePhTin(c.tin, c.tin_branch_code) : '')
    setFInvoice('')
    setSiLines([])
    if (id && companyId) {
      const { data } = await supabase.from('sales_invoices')
        .select('id,si_number,date,total_amount')
        .eq('company_id', companyId).eq('customer_id', id).eq('status', 'posted').order('date')
      setOpenSIs(data as SIRef[] || [])
    } else {
      setOpenSIs([])
    }
  }

  const onInvoiceChange = async (siId: string) => {
    setFInvoice(siId)
    setSiLines([])
    if (!siId) { setLines([newLine()]); return }
    const { data: lns } = await supabase.from('sales_invoice_lines')
      .select('*').eq('sales_invoice_id', siId).order('line_number')
    if (lns && lns.length > 0) {
      const mapped: CMLLine[] = lns.map(l => {
        const vc = vatCodes.find(v => v.id === l.vat_code_id)
        return {
          _key: l.id, id: l.id, invoice_line_id: l.id, item_id: l.item_id || '',
          description: l.description, quantity: Number(l.quantity), unit_price: Number(l.unit_price),
          net_amount: Number(l.net_amount), vat_code_id: l.vat_code_id || '',
          vat_classification: (vc?.vat_classification || 'regular') as CMLLine['vat_classification'],
          vat_rate: vc?.rate ?? 12, vat_amount: Number(l.vat_amount), total_amount: Number(l.total_amount),
          revenue_account_id: l.revenue_account_id || '',
        }
      })
      setSiLines(lns as SILine[])
      setLines(mapped)
    }
  }

  const setLineField = (key: string, field: keyof CMLLine, value: string | number) => {
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      if (field === 'vat_code_id') {
        const vc = vatCodes.find(v => v.id === value)
        return computeLine({ ...l, vat_code_id: value as string, vat_classification: vc?.vat_classification || 'regular', vat_rate: vc?.rate ?? 12 })
      }
      return computeLine({ ...l, [field]: value })
    }))
  }

  const openNew = () => {
    setEditDoc(null); setFCustomer(''); setFCustomerName(''); setFCustomerTIN('')
    setFDate(today()); setFBranch(branchId); setFInvoice(''); setFReason(''); setFRemarks('')
    setLines([newLine()]); setOpenSIs([]); setSiLines([]); setError('')
    setMode('new')
  }

  const openEdit = async (doc: CM) => {
    setEditDoc(doc)
    const c = customers.find(x => x.id === doc.customer_id)
    setFCustomer(doc.customer_id); setFCustomerName(doc.customer_name_snapshot); setFCustomerTIN(doc.customer_tin_snapshot)
    setFDate(doc.cm_date); setFBranch(doc.branch_id)
    setFInvoice(doc.invoice_id || ''); setFReason(doc.reason_code_id); setFRemarks(doc.remarks || '')
    setError('')
    if (doc.customer_id && companyId) {
      const { data } = await supabase.from('sales_invoices')
        .select('id,si_number,date,total_amount').eq('company_id', companyId)
        .eq('customer_id', doc.customer_id).eq('status', 'posted').order('date')
      setOpenSIs(data as SIRef[] || [])
    }
    const { data: lns } = await supabase.from('credit_memo_lines').select('*').eq('credit_memo_id', doc.id).order('line_number')
    if (lns && lns.length > 0) {
      setLines(lns.map(l => {
        const vc = vatCodes.find(v => v.id === l.vat_code_id)
        return {
          _key: l.id, id: l.id, invoice_line_id: l.invoice_line_id || '', item_id: l.item_id || '',
          description: l.description, quantity: Number(l.quantity), unit_price: Number(l.unit_price),
          net_amount: Number(l.net_amount), vat_code_id: l.vat_code_id || '',
          vat_classification: (vc?.vat_classification || 'regular') as CMLLine['vat_classification'],
          vat_rate: vc?.rate ?? 12, vat_amount: Number(l.vat_amount), total_amount: Number(l.total_amount),
          revenue_account_id: l.revenue_account_id || '',
        }
      }))
    } else setLines([newLine()])
    setMode(doc.status === 'draft' ? 'edit' : 'view')
    void c
  }

  const totalNet = lines.reduce((s, l) => s + l.net_amount, 0)
  const totalVAT = lines.reduce((s, l) => s + l.vat_amount, 0)
  const totalAmt = lines.reduce((s, l) => s + l.total_amount, 0)
  const requiredConfig = useMemo<ConfigField[]>(
    () => totalVAT > 0.005 ? ['ar_account_id', 'vat_payable_account_id'] : ['ar_account_id'],
    [totalVAT]
  )
  const readiness = useTransactionReadiness({
    companyId,
    branchId: fBranch || branchId,
    documentCode: 'CM',
    postingDate: fDate,
    requiredConfig,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0
  const glPreviewRows = useMemo<GLImpactRow[]>(() => [
    ...lines
      .filter(line => line.net_amount > 0.005)
      .map(line => ({
        accountId: line.revenue_account_id || null,
        description: line.description || 'Revenue reversal',
        debit: line.net_amount,
        credit: 0,
      })),
    ...(totalVAT > 0.005 ? [{
      configKey: 'vat_payable_account_id' as const,
      description: 'Output VAT reversal',
      debit: totalVAT,
      credit: 0,
    }] : []),
    {
      configKey: 'ar_account_id',
      description: 'Reduce accounts receivable',
      debit: 0,
      credit: totalAmt,
    },
  ], [lines, totalAmt, totalVAT])

  const save = async (nextStatus: CMStatus = 'draft') => {
    if (setupBlocked) {
      setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0])
      return
    }
    if (!companyId || !fCustomer || !fReason) { setError('Customer and Reason Code are required.'); return }
    if (lines.every(l => !l.description.trim())) { setError('At least one line is required.'); return }
    setSaving(true); setError('')
    try {
      const header = {
        company_id: companyId, branch_id: fBranch || branchId,
        customer_id: fCustomer, customer_name_snapshot: fCustomerName, customer_tin_snapshot: fCustomerTIN || '',
        invoice_id: fInvoice || '', cm_date: fDate,
        reason_code_id: fReason, remarks: fRemarks || '',
      }
      const linesPayload = lines
        .filter(l => l.description.trim())
        .map(l => ({
          invoice_line_id: l.invoice_line_id || '', item_id: l.item_id || '',
          description: l.description, quantity: l.quantity, unit_price: l.unit_price,
          vat_code_id: l.vat_code_id || '', revenue_account_id: l.revenue_account_id || '',
        }))
      const { error: rpcErr } = await supabase.rpc('fn_save_credit_memo', {
        p_cm_id: (mode === 'new' ? null : (editDoc?.id ?? null))!,
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
  const cmStatus = editDoc?.status || 'draft'
  const auditFacts = editDoc ? [
    { label: 'Created', value: formatDateTime(editDoc.created_at) },
    { label: 'Last edited', value: formatDateTime(editDoc.updated_at) },
    { label: 'Posted', value: formatDateTime(editDoc.posted_at) },
    { label: 'Status', value: editDoc.status },
    { label: 'Lock status', value: editDoc.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ] : []

  // ── List ───────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search CM#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as CMStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            {(['', 'draft', 'approved', 'applied', 'cancelled'] as const).map(s => (
              <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'All Statuses'}</option>
            ))}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={openNew}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Credit Memo
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Credit Memos.</div>
        ) : loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}
          </div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Credit Memos found</p>
            <p className="text-xs text-gray-400 mt-1">{search || filterStatus ? 'No records match the current filters.' : 'Create your first Credit Memo.'}</p>
            {!search && !filterStatus && <button onClick={openNew} className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">New Credit Memo</button>}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['CM Date','CM Number','Customer','Related Invoice','Reason','Net Amount','VAT','Total','Status'].map(h => (
                    <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {list.map(cm => (
                  <tr key={cm.id} onClick={() => openEdit(cm)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                    <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={cm.cm_date} /></td>
                    <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{cm.cm_number}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{cm.customer_name_snapshot}</td>
                    <td className="px-4 py-2.5 font-mono text-xs text-gray-500">{openSIs.find(s => s.id === cm.invoice_id)?.si_number || (cm.invoice_id ? '…' : '—')}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-500 max-w-[140px] truncate">{reasonCodes.find(r => r.id === cm.reason_code_id)?.description || '—'}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-600"><AmountCell amount={cm.total_net_amount} /></td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-500"><AmountCell amount={cm.total_vat_amount} /></td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={cm.total_amount} /></td>
                    <td className="px-4 py-2.5"><StatusBadge status={statusMap[cm.status]} label={cm.status.charAt(0).toUpperCase() + cm.status.slice(1)} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    )
  }

  // ── Form / View Workspace ───────────────────────────────────
  const selectedCustomer = customers.find(customer => customer.id === fCustomer)
  const selectedInvoice = openSIs.find(invoice => invoice.id === fInvoice)
  const selectedReason = reasonCodes.find(reasonCode => reasonCode.id === fReason)
  const selectedBranch = branches.find(branch => branch.id === fBranch)
  const workflowSteps = [{ key: 'draft', label: 'Draft' }, { key: 'approved', label: 'Approved' }, { key: 'applied', label: 'Applied' }, { key: 'cancelled', label: 'Voided' }]
  const validationErrors = [
    !fCustomer ? 'Customer is required.' : '',
    !fReason ? 'Reason code is required.' : '',
    lines.every(line => !line.description.trim()) ? 'At least one credit line is required.' : '',
    lines.some(line => line.quantity <= 0) ? 'Line quantities must be greater than zero.' : '',
    lines.some(line => line.net_amount > 0 && !line.revenue_account_id) ? 'Revenue account mapping is required for credit lines before application.' : '',
    lines.some(line => line.vat_amount > 0 && !line.vat_code_id) ? 'VAT code is required for taxable credit lines.' : '',
  ].filter(Boolean)

  return (
    <TransactionWorkspace
      title="Credit Memo"
      documentNo={editDoc?.cm_number}
      status={cmStatus}
      statusLabel={cmStatus}
      family="sales"
      identity={{ name: fCustomerName || selectedCustomer?.registered_name || 'Customer not selected', secondary: fCustomerTIN || undefined }}
      metrics={[
        { label: 'Credit Total', value: `₱${fmt(totalAmt)}`, emphasis: true },
        { label: 'VAT Reversed', value: `₱${fmt(totalVAT)}` },
        { label: 'Net Credit', value: `₱${fmt(totalNet)}` },
      ]}
      meta={[
        { label: 'Mode', value: readOnly ? 'Read only' : 'Editable', tone: readOnly ? 'warning' : 'info' },
        { label: 'Posting', value: editDoc?.posted_at ? 'Posted / applied' : 'Not applied', tone: editDoc?.posted_at ? 'success' : 'neutral' },
      ]}
      actions={[
        ...((mode === 'new' || cmStatus === 'draft') && !readOnly ? [
          { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: () => save('draft'), disabled: saving || setupBlocked },
          { key: 'approve', label: 'Submit for Approval', onClick: () => save('approved'), disabled: saving || setupBlocked },
          { key: 'apply', label: 'Apply', onClick: () => save('applied'), disabled: saving || setupBlocked, variant: 'primary' as const },
        ] : []),
        ...(cmStatus === 'approved' ? [
          { key: 'revert', label: saving ? 'Reverting…' : 'Revert to Draft', onClick: () => save('draft'), disabled: saving, group: 'more' as const },
          { key: 'apply-approved', label: 'Apply', onClick: () => save('applied'), disabled: saving || setupBlocked, variant: 'primary' as const },
        ] : []),
      ]}
      workflow={{ steps: workflowSteps, currentKey: cmStatus }}
      cards={[
        { title: 'Document Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className={lbl}>Credit Memo Date<input type="date" value={fDate} onChange={event => setFDate(event.target.value)} disabled={readOnly} className={`${readOnly ? ro : inp} mt-1`} /></label><label className={lbl}>Branch<select value={fBranch} onChange={event => setFBranch(event.target.value)} disabled={readOnly} className={`${readOnly ? ro : inp} mt-1`}><option value="">Select branch…</option>{branches.map(branch => <option key={branch.id} value={branch.id}>{branch.branch_code} – {branch.branch_name}</option>)}</select></label><div><div className="pxl-field-label">Credit Memo Number</div><div className="pxl-body-text mt-1 font-mono">{editDoc?.cm_number || 'Generated on save'}</div></div><div><div className="pxl-field-label">Lock State</div><div className="pxl-body-text mt-1">{cmStatus === 'draft' ? 'Editable draft' : 'Lifecycle controlled'}</div></div></div> },
        { title: 'Customer Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className={`${lbl} sm:col-span-2`}>Customer{readOnly ? <div className={`${ro} mt-1`}>{fCustomerName}</div> : <select value={fCustomer} onChange={event => void onCustomerChange(event.target.value)} className={`${inp} mt-1`}><option value="">Select customer…</option>{customers.map(customer => <option key={customer.id} value={customer.id}>{customer.registered_name}</option>)}</select>}</label><div><div className="pxl-field-label">Customer TIN</div><div className="pxl-body-text mt-1 font-mono">{fCustomerTIN || '—'}</div></div><div><div className="pxl-field-label">Credit Context</div><div className="pxl-body-text mt-1">Accounts receivable reduction</div></div></div> },
        { title: 'Sales Context', content: <div className="grid gap-3 sm:grid-cols-2"><label className={lbl}>Related Invoice{readOnly ? <div className={`${ro} mt-1`}>{selectedInvoice?.si_number || (fInvoice ? 'Source invoice snapshot' : 'Standalone')}</div> : <select value={fInvoice} onChange={event => void onInvoiceChange(event.target.value)} className={`${inp} mt-1`} disabled={!fCustomer}><option value="">None (standalone)</option>{openSIs.map(invoice => <option key={invoice.id} value={invoice.id}>{invoice.si_number} — {new Date(invoice.date).toLocaleDateString('en-PH')}</option>)}</select>}</label><label className={lbl}>Reason Code{readOnly ? <div className={`${ro} mt-1`}>{selectedReason?.description || '—'}</div> : <select value={fReason} onChange={event => setFReason(event.target.value)} className={`${inp} mt-1`}><option value="">Select reason…</option>{reasonCodes.map(reasonCode => <option key={reasonCode.id} value={reasonCode.id}>{reasonCode.description}</option>)}</select>}</label><div><div className="pxl-field-label">Source Lines</div><div className="pxl-body-text mt-1">{fInvoice && siLines.length > 0 ? 'Copied from Sales Invoice' : 'Standalone credit lines'}</div></div><div><div className="pxl-field-label">Application Status</div><div className="pxl-body-text mt-1">{cmStatus}</div></div></div> },
      ]}
      tabBadges={{ lines: lines.length }}
      tabContent={{
        lines: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]"><div className="flex items-center justify-between border-b border-[var(--pxl-border-medium)] px-3 py-2"><h2 className="pxl-section-title">Credit Lines {fInvoice && siLines.length > 0 ? '· From Invoice' : ''}</h2>{canEdit && !fInvoice && <button onClick={() => setLines(current => [...current, newLine()])} className="pxl-button pxl-button--text">+ Add Line</button>}</div><table className="pxl-data-grid w-full text-xs"><thead><tr>{['#', 'Description', 'Qty', 'Unit Price', 'Net Amount', 'VAT Code', 'VAT', 'Total', ''].map(label => <th key={label} className={['Qty', 'Unit Price', 'Net Amount', 'VAT', 'Total'].includes(label) ? 'text-right' : 'text-left'}>{label}</th>)}</tr></thead><tbody>{lines.map((line, index) => <tr key={line._key}><td className="text-right text-gray-500">{index + 1}</td><td>{canEdit && !fInvoice ? <input value={line.description} onChange={event => setLineField(line._key, 'description', event.target.value)} className="w-full rounded border px-2 py-1" /> : line.description}</td><td className="text-right">{canEdit && !fInvoice ? <input type="number" value={line.quantity} min={0} onChange={event => setLineField(line._key, 'quantity', Number(event.target.value) || 0)} className="w-16 rounded border px-2 py-1 text-right" /> : <span className="font-mono">{line.quantity}</span>}</td><td className="text-right">{canEdit && !fInvoice ? <input type="number" value={line.unit_price} min={0} onChange={event => setLineField(line._key, 'unit_price', Number(event.target.value) || 0)} className="w-24 rounded border px-2 py-1 text-right" /> : <span className="font-mono">{fmt(line.unit_price)}</span>}</td><td className="text-right font-mono">{fmt(line.net_amount)}</td><td>{canEdit && !fInvoice ? <select value={line.vat_code_id} onChange={event => setLineField(line._key, 'vat_code_id', event.target.value)} className="w-24 rounded border px-1.5 py-1"><option value="">—</option>{vatCodes.map(vatCode => <option key={vatCode.id} value={vatCode.id}>{vatCode.vat_code}</option>)}</select> : vatCodes.find(vatCode => vatCode.id === line.vat_code_id)?.vat_code || '—'}</td><td className="text-right font-mono">{fmt(line.vat_amount)}</td><td className="text-right font-mono font-semibold">{fmt(line.total_amount)}</td><td>{canEdit && !fInvoice && <button onClick={() => setLines(current => current.filter(item => item._key !== line._key))} className="text-red-600" aria-label={`Remove credit line ${index + 1}`}>✕</button>}</td></tr>)}</tbody></table></div>,
        financial: <div className="ml-auto grid max-w-lg grid-cols-2 gap-2"><span className="text-gray-600">Gross Credit</span><span className="text-right font-mono">₱{fmt(totalAmt)}</span><span className="text-gray-600">Net Credit</span><span className="text-right font-mono">₱{fmt(totalNet)}</span><span className="text-gray-600">Output VAT Reversed</span><span className="text-right font-mono">₱{fmt(totalVAT)}</span><span className="pxl-section-title border-t pt-2">AR Reduction</span><span className="border-t pt-2 text-right font-mono font-bold">₱{fmt(totalAmt)}</span></div>,
        gl: <GLImpactPanel companyId={companyId} sourceDocType="CM" sourceDocId={editDoc && editDoc.status !== 'draft' ? editDoc.id : null} previewRows={glPreviewRows} />,
        tax: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]"><table className="pxl-data-grid w-full"><thead><tr>{['VAT Classification', 'Tax Base Reversed', 'Rate', 'VAT Reversed', 'Source Lines'].map(label => <th key={label} className={['Tax Base Reversed', 'Rate', 'VAT Reversed', 'Source Lines'].includes(label) ? 'text-right' : 'text-left'}>{label}</th>)}</tr></thead><tbody>{(['regular', 'zero_rated', 'exempt'] as const).map(classification => { const classLines = lines.filter(line => line.vat_classification === classification); return <tr key={classification}><td>{classification.replace('_', ' ')}</td><td className="text-right font-mono">₱{fmt(classLines.reduce((sum, line) => sum + line.net_amount, 0))}</td><td className="text-right font-mono">{classification === 'regular' ? `${classLines[0]?.vat_rate || 0}%` : classification === 'zero_rated' ? '0%' : 'Exempt'}</td><td className="text-right font-mono">₱{fmt(classLines.reduce((sum, line) => sum + line.vat_amount, 0))}</td><td className="text-right font-mono">{classLines.length}</td></tr>})}</tbody></table></div>,
        validation: <div className="space-y-2"><SetupReadinessBanner readiness={readiness} />{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{validationErrors.length > 0 ? validationErrors.map(message => <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Credit, tax-reversal, and source-document controls are ready.</div>}</div>,
        workflow: <ol className="grid gap-2 sm:grid-cols-4">{workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === cmStatus ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
        approval: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Approval Status</div><div className="pxl-body-text mt-1">{cmStatus === 'draft' ? 'Not submitted' : cmStatus === 'approved' ? 'Approved' : cmStatus === 'applied' ? 'Approved and applied' : 'Cancelled'}</div></div><div><div className="pxl-field-label">Control</div><div className="pxl-body-text mt-1">Status and permission controlled</div></div><div><div className="pxl-field-label">Next Action</div><div className="pxl-body-text mt-1">{cmStatus === 'draft' ? 'Submit for Approval' : cmStatus === 'approved' ? 'Apply' : 'No approval action available'}</div></div></div>,
        audit: editDoc?.id ? <div className="space-y-4"><div className="grid gap-3 sm:grid-cols-5">{auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div><AuditTrailSection tableName="credit_memos" recordId={editDoc.id} /></div> : <TransactionEmptyState>Audit history begins after the Credit Memo is saved.</TransactionEmptyState>,
        related: fInvoice ? <table className="pxl-data-grid w-full"><thead><tr><th className="text-left">Relationship</th><th className="text-left">Document</th><th className="text-left">Date</th><th className="text-left">Open</th></tr></thead><tbody><tr><td>Credits</td><td className="font-mono font-semibold">{selectedInvoice?.si_number || fInvoice}</td><td>{selectedInvoice?.date || 'Source snapshot'}</td><td><Link to={`/sales-invoices/${fInvoice}`} className="text-blue-700 hover:underline">Sales Invoice</Link></td></tr></tbody></table> : <TransactionEmptyState>This is a standalone Credit Memo with no related Sales Invoice.</TransactionEmptyState>,
        party: selectedCustomer ? <dl className="grid gap-3 sm:grid-cols-2"><div><dt className="pxl-field-label">Customer</dt><dd className="pxl-body-text mt-1">{selectedCustomer.registered_name}</dd></div><div><dt className="pxl-field-label">TIN</dt><dd className="pxl-body-text mt-1 font-mono">{composePhTin(selectedCustomer.tin, selectedCustomer.tin_branch_code)}</dd></div></dl> : <TransactionEmptyState>Select a customer to see related-party information.</TransactionEmptyState>,
        activity: <div className="grid gap-3 sm:grid-cols-5">{auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div>,
        notes: <label className={lbl}>Credit Memo Remarks<textarea value={fRemarks} onChange={event => setFRemarks(event.target.value)} disabled={readOnly} rows={5} className={`${readOnly ? ro : inp} mt-1 resize-none`} /></label>,
        system: <SystemMetadataPanel facts={[
          { label: 'Internal ID', value: editDoc?.id || 'Assigned when saved', hint: 'Transaction identity' },
          { label: 'Document Number', value: editDoc?.cm_number || 'Generated from number series', hint: 'Credit Memo number' },
          { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
          { label: 'Branch', value: selectedBranch ? `${selectedBranch.branch_code} — ${selectedBranch.branch_name}` : fBranch || '—', hint: 'Posting context' },
          { label: 'Source Invoice', value: fInvoice || 'Standalone', hint: 'Document lineage' },
          { label: 'Created', value: formatDateTime(editDoc?.created_at), hint: 'Audit metadata' },
          { label: 'Updated', value: formatDateTime(editDoc?.updated_at), hint: 'Audit metadata' },
          { label: 'Posted / Applied', value: formatDateTime(editDoc?.posted_at), hint: 'Lifecycle metadata' },
          { label: 'Lock Status', value: cmStatus === 'draft' ? 'Editable draft' : 'Lifecycle controlled', hint: 'Immutability control' },
        ]} />,
      }}
      emptyTabMessages={{ attachments: 'No attachments have been added to this Credit Memo.' }}
      sidebarPanels={[
        { key: 'balance', title: 'Credit Balance', content: <div className="flex justify-between gap-3"><span className="pxl-field-label">Total Credit</span><span className="font-mono text-sm font-bold">₱{fmt(totalAmt)}</span></div> },
        { key: 'tax', title: 'Tax', content: <div className="flex justify-between gap-3"><span className="pxl-field-label">VAT Reversed</span><span className="font-mono text-xs">₱{fmt(totalVAT)}</span></div> },
        { key: 'gl', title: 'GL Preview', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Debit</span><span className="font-mono text-xs">₱{fmt(glPreviewRows.reduce((sum, row) => sum + row.debit, 0))}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Credit</span><span className="font-mono text-xs">₱{fmt(glPreviewRows.reduce((sum, row) => sum + row.credit, 0))}</span></div></div> },
        { key: 'customer', title: 'Customer', content: <div><div className="text-xs font-semibold">{fCustomerName || selectedCustomer?.registered_name || 'Not selected'}</div><div className="pxl-caption mt-1 font-mono">{fCustomerTIN || 'No TIN'}</div></div> },
        { key: 'audit', title: 'Audit', content: <p className="pxl-caption">{cmStatus === 'draft' ? 'Draft remains editable.' : 'Document is frozen by lifecycle controls.'}</p> },
      ]}
      footer={<span>Created {formatDateTime(editDoc?.created_at)} · Updated {formatDateTime(editDoc?.updated_at)} · {cmStatus === 'draft' ? 'Editable draft' : 'Lifecycle controlled'}</span>}
      onBack={() => setMode('list')}
      backLabel="Credit Memos"
    />
  )
}
