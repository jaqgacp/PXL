import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'

// ── Types ─────────────────────────────────────────────────────
type RStatus = 'draft' | 'posted' | 'bounced' | 'cancelled'

type Receipt = {
  id: string; receipt_number: string; receipt_date: string
  customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string
  branch_id: string | null
  payment_mode_id: string; reference_number: string | null
  bank_account_id: string | null; total_amount: number; total_cwt: number
  remarks: string | null; status: RStatus; posted_at: string | null
  created_at: string; updated_at?: string | null
}

type ApplicationLine = {
  _key: string
  line_type: 'invoice_application' | 'customer_advance'
  invoice_id: string; si_number: string; si_date: string
  original_amount: number; balance_due: number
  payment_amount: number; cwt_amount: number; forex_adjustment: number
  atc_code_id: string | null
  // CWT taxable base = VAT-exclusive income payment (PXL-AUD-031).
  // net_ratio = (invoice total − VAT) / invoice total; base_auto tracks
  // whether the base still follows the applied amount automatically.
  cwt_tax_base: number
  cwt_variance_reason: string
  net_ratio: number
  base_auto: boolean
}

const CWT_VARIANCE_REASONS = [
  { value: 'rounding', label: 'Rounding' },
  { value: 'partial_non_taxable', label: 'Partially non-taxable' },
  { value: 'bir_ruling', label: 'BIR ruling' },
  { value: 'supplier_exempt', label: 'Payee exempt' },
  { value: 'other_authorized', label: 'Other (authorized)' },
]

type CustomerRef = {
  id: string; registered_name: string; tin: string; tin_branch_code: string; registered_address: string
  is_subject_to_cwt: boolean; default_cwt_atc_code_id: string | null
}

type PaymentMode = { id: string; code: string; name: string }
type COAAccount  = { id: string; account_code: string; account_name: string }
type Branch      = { id: string; branch_code: string; branch_name: string }
type ATCCode     = { id: string; code: string; description: string; rate: number }

// ── Helpers ──────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]
const round2 = (n: number) => Math.round(n * 100) / 100
const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'

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
  const requiredConfig = useMemo<ConfigField[]>(
    () => {
      const fields: ConfigField[] = ['ar_account_id', 'default_cash_account_id']
      if (lines.some(line => line.cwt_amount > 0.005)) fields.push('ewt_withheld_account_id')
      if (lines.some(line => line.line_type === 'customer_advance' && line.payment_amount + line.cwt_amount > 0.005)) {
        fields.push('customer_advances_account_id')
      }
      return fields
    },
    [lines]
  )
  const readiness = useTransactionReadiness({
    companyId,
    branchId: mode === 'list' ? branchId : fBranch,
    documentCode: 'OR',
    postingDate: mode === 'list' ? today() : fDate,
    requiredConfig,
  })

  // Load reference data
  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,tin,tin_branch_code,registered_address,is_subject_to_cwt,default_cwt_atc_code_id')
        .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('ref_payment_modes').select('id,code,name').eq('is_active', true).order('sort_order'),
      supabase.from('chart_of_accounts')
        .select('id,account_code,account_name')
        .eq('company_id', companyId).eq('account_type', 'asset').eq('is_postable', true).eq('is_active', true)
        .order('account_code'),
      supabase.from('branches').select('id,branch_code,branch_name')
        .eq('company_id', companyId).eq('is_active', true),
      supabase.from('atc_codes').select('id,code,description,rate').eq('is_active', true).eq('tax_category', 'ewt').order('code'),
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
      .select('id,si_number,date,total_amount,total_vat_amount')
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

    const customer = customers.find(c => c.id === customerId)
    const defaultAtcId = customer?.is_subject_to_cwt ? customer.default_cwt_atc_code_id : null
    const defaultAtc = atcCodes.find(a => a.id === defaultAtcId)

    const openLines: ApplicationLine[] = sis.map(si => {
      const totalPaid = (applied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.payment_amount) + Number(a.cwt_amount), 0)
      const totalCM = (cmApplied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.total_amount), 0)
      const balance = Number(si.total_amount) - totalPaid - totalCM
      // CWT base defaults to the VAT-exclusive proportion of the amount
      // applied (statutory base per RR 2-98) — PXL-AUD-031/045.
      const netRatio = Number(si.total_amount) > 0
        ? (Number(si.total_amount) - Number(si.total_vat_amount || 0)) / Number(si.total_amount)
        : 1
      const defaultBase = defaultAtc ? round2(balance * netRatio) : 0
      const defaultCwt = defaultAtc ? round2(defaultBase * defaultAtc.rate / 100) : 0
      return {
        _key: si.id,
        line_type: 'invoice_application' as const,
        invoice_id: si.id, si_number: si.si_number, si_date: si.date,
        original_amount: Number(si.total_amount), balance_due: balance,
        payment_amount: defaultAtc ? round2(Math.max(balance - defaultCwt, 0)) : 0,
        cwt_amount: defaultCwt,
        forex_adjustment: 0,
        atc_code_id: defaultAtcId,
        cwt_tax_base: defaultBase,
        cwt_variance_reason: '',
        net_ratio: netRatio,
        base_auto: true,
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
    if (readiness.blockers.length > 0) {
      setError('Complete company, branch, fiscal period, number series, and GL posting setup before creating a receipt.')
      return
    }
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
    setFDate(doc.receipt_date); setFBranch(doc.branch_id || branchId)
    setFMode(doc.payment_mode_id); setFRef(doc.reference_number || '')
    setFBankAccount(doc.bank_account_id || ''); setFRemarks(doc.remarks || '')
    setError('')

    // Load existing applied lines
    const { data: rl } = await supabase.from('receipt_lines')
      .select('*').eq('receipt_id', doc.id)
    const invoiceIds = (rl || []).map(r => r.invoice_id).filter((id): id is string => Boolean(id))
    const { data: siData } = invoiceIds.length
      ? await supabase.from('sales_invoices').select('id,si_number,date,total_amount,total_vat_amount')
          .in('id', invoiceIds)
      : { data: [] }

    const mapped: ApplicationLine[] = (rl || []).map(r => {
      const si = (siData || []).find(s => s.id === r.invoice_id)
      const siTotal = Number(si?.total_amount || 0)
      const isAdvance = r.line_type === 'customer_advance' || !r.invoice_id
      return {
        _key: r.id,
        line_type: isAdvance ? 'customer_advance' : 'invoice_application',
        invoice_id: r.invoice_id || '', si_number: isAdvance ? 'Customer Advance' : si?.si_number || '—',
        si_date: si?.date || '', original_amount: siTotal,
        balance_due: isAdvance ? Number(r.payment_amount) + Number(r.cwt_amount) : 0,
        payment_amount: Number(r.payment_amount), cwt_amount: Number(r.cwt_amount),
        forex_adjustment: Number(r.forex_adjustment), atc_code_id: r.atc_code_id || null,
        cwt_tax_base: Number(r.cwt_tax_base || 0),
        cwt_variance_reason: r.cwt_variance_reason || '',
        net_ratio: siTotal > 0 ? (siTotal - Number(si?.total_vat_amount || 0)) / siTotal : 1,
        base_auto: false,
      }
    })
    setLines(mapped)
    setMode(doc.status === 'draft' ? 'edit' : 'view')
  }

  const addCustomerAdvanceLine = () => {
    const customer = customers.find(c => c.id === fCustomer)
    setLines(prev => [...prev, {
      _key: crypto.randomUUID(),
      line_type: 'customer_advance',
      invoice_id: '',
      si_number: 'Customer Advance',
      si_date: fDate,
      original_amount: 0,
      balance_due: 0,
      payment_amount: 0,
      cwt_amount: 0,
      forex_adjustment: 0,
      atc_code_id: customer?.is_subject_to_cwt ? customer.default_cwt_atc_code_id : null,
      cwt_tax_base: 0,
      cwt_variance_reason: '',
      net_ratio: 1,
      base_auto: true,
    }])
  }

  const setLineField = (lineKey: string, field: 'payment_amount' | 'cwt_amount' | 'forex_adjustment' | 'cwt_tax_base', val: number) => {
    setLines(prev => prev.map(l => {
      if (l._key !== lineKey) return l
      const next = { ...l, [field]: val }
      if (field === 'cwt_amount' && val > 0 && !next.atc_code_id) {
        const customer = customers.find(c => c.id === fCustomer)
        next.atc_code_id = customer?.default_cwt_atc_code_id || null
      }
      if (field === 'cwt_tax_base') {
        next.base_auto = false
      } else if (next.base_auto && (field === 'payment_amount' || field === 'cwt_amount')) {
        // Keep the base tracking the VAT-exclusive proportion of the amount
        // applied until the user takes over the base manually.
        next.cwt_tax_base = round2((next.payment_amount + next.cwt_amount) * next.net_ratio)
      }
      // A changed amount invalidates a previously chosen variance reason if
      // the amounts now agree with the ATC rate again.
      const atc = atcCodes.find(a => a.id === next.atc_code_id)
      if (atc && next.cwt_amount > 0 && next.cwt_tax_base > 0) {
        const expected = round2(next.cwt_tax_base * atc.rate / 100)
        if (Math.abs(expected - next.cwt_amount) <= 0.02) next.cwt_variance_reason = ''
      }
      return next
    }))
  }

  const setLineVarianceReason = (lineKey: string, reason: string) => {
    setLines(prev => prev.map(l => l._key === lineKey ? { ...l, cwt_variance_reason: reason } : l))
  }

  const setLineAtc = (lineKey: string, atcCodeId: string | null) => {
    setLines(prev => prev.map(l => l._key === lineKey ? { ...l, atc_code_id: atcCodeId } : l))
  }

  const totalPayment = lines.reduce((s, l) => s + l.payment_amount, 0)
  const totalCWT = lines.reduce((s, l) => s + l.cwt_amount, 0)
  const appliedLines = lines.filter(l => l.payment_amount > 0 || l.cwt_amount > 0)
  const invoiceAppliedGross = appliedLines
    .filter(l => l.line_type === 'invoice_application')
    .reduce((s, l) => s + l.payment_amount + l.cwt_amount, 0)
  const advanceGross = appliedLines
    .filter(l => l.line_type === 'customer_advance')
    .reduce((s, l) => s + l.payment_amount + l.cwt_amount, 0)
  const glImpactRows: GLImpactRow[] = [
    {
      accountId: fBankAccount || null,
      configKey: fBankAccount ? undefined : 'default_cash_account_id',
      description: 'Cash received',
      debit: totalPayment,
      credit: 0,
    },
    { configKey: 'ewt_withheld_account_id', description: 'CWT withheld by customer', debit: totalCWT, credit: 0 },
    { configKey: 'ar_account_id', description: 'Accounts receivable cleared', debit: 0, credit: invoiceAppliedGross },
    { configKey: 'customer_advances_account_id', description: 'Customer advance liability', debit: 0, credit: advanceGross },
  ]

  const save = async (nextStatus: RStatus = 'draft') => {
    if (!companyId || !fCustomer || !fMode) {
      setError('Customer and Payment Mode are required.')
      return
    }
    if (readiness.blockers.length > 0) {
      setError('Complete setup readiness blockers before saving or posting this receipt.')
      return
    }
    if (appliedLines.length === 0) {
      setError('At least one invoice or customer advance line must have an amount.')
      return
    }
    for (const line of appliedLines) {
      if (line.cwt_amount > 0 && !line.atc_code_id) {
        setError(`ATC code is required when CWT is recorded for ${line.si_number}.`)
        return
      }
      const atc = atcCodes.find(a => a.id === line.atc_code_id)
      if (line.cwt_amount > 0 && atc) {
        const base = line.cwt_tax_base > 0 ? round2(line.cwt_tax_base) : round2(line.payment_amount + line.cwt_amount)
        if (base <= 0) {
          setError(`CWT taxable base is required for ${line.si_number}.`)
          return
        }
        const expected = round2(base * atc.rate / 100)
        if (Math.abs(expected - line.cwt_amount) > 0.02 && !line.cwt_variance_reason) {
          setError(`CWT for ${line.si_number} should be ${fmt(expected)} (${atc.rate}% of base ${fmt(base)}, ATC ${atc.code}). Select a variance reason to keep ${fmt(line.cwt_amount)}.`)
          return
        }
      }
    }
    setSaving(true); setError('')
    try {
      const isNew = mode === 'new'

      const header = {
        company_id: companyId,
        branch_id: fBranch || branchId,
        customer_id: fCustomer,
        customer_name_snapshot: fCustomerName,
        customer_tin_snapshot: fCustomerTIN,
        receipt_date: fDate,
        payment_mode_id: fMode,
        reference_number: fRef || null,
        bank_account_id: fBankAccount || null,
        total_amount: totalPayment,
        total_cwt: totalCWT,
        remarks: fRemarks || null,
      }

      const linesPayload = appliedLines.map(l => ({
        line_type: l.line_type,
        invoice_id: l.line_type === 'invoice_application' ? l.invoice_id : null,
        payment_amount: l.payment_amount,
        cwt_amount: l.cwt_amount,
        forex_adjustment: l.forex_adjustment,
        atc_code_id: l.cwt_amount > 0 ? l.atc_code_id : null,
        cwt_tax_base: l.cwt_amount > 0 && l.cwt_tax_base > 0 ? l.cwt_tax_base : null,
        cwt_variance_reason: l.cwt_amount > 0 && l.cwt_variance_reason ? l.cwt_variance_reason : null,
      }))

      const { data: docId, error: saveErr } = await supabase.rpc('fn_save_receipt', {
        p_receipt_id: (isNew ? null : editDoc!.id)!,
        p_header: header,
        p_lines: linesPayload,
      })
      if (saveErr) throw saveErr

      if (nextStatus === 'posted') {
        const { error: postErr } = await supabase.rpc('fn_post_receipt', { p_receipt_id: docId })
        if (postErr) throw postErr
      }

      setMode('list')
    } catch (e) { setError(e instanceof Error ? e.message : 'Save failed.') }
    setSaving(false)
  }

  // Bounce — SECURITY DEFINER RPC bypasses RLS for posted rows
  const doBounce = async () => {
    if (!editDoc) return
    setSaving(true)
    const { error: e } = await supabase.rpc('fn_bounce_receipt', { p_receipt_id: editDoc.id })
    if (e) { setError(e.message); setSaving(false); return }
    setMode('list')
    setSaving(false)
  }

  const readOnly = mode === 'view'
  const canEdit = mode === 'new' || mode === 'edit'
  const auditFacts = editDoc ? [
    { label: 'Created', value: formatDateTime(editDoc.created_at) },
    { label: 'Last edited', value: formatDateTime(editDoc.updated_at) },
    { label: 'Posted', value: formatDateTime(editDoc.posted_at) },
    { label: 'Lock status', value: editDoc.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ] : []

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
            <button onClick={openNew} disabled={readiness.loading || readiness.blockers.length > 0}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              Receive Payment
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {companyId && readiness.blockers.length > 0 && (
          <div className="px-5 py-3 border-b border-gray-100">
            <SetupReadinessBanner readiness={readiness} />
          </div>
        )}

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
              <button onClick={openNew} disabled={readiness.loading || readiness.blockers.length > 0}
                className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed">
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
          <button onClick={() => save('draft')} disabled={saving || readiness.blockers.length > 0}
            className="px-3 py-1.5 border border-gray-300 rounded text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">
            {saving ? 'Saving…' : 'Save Draft'}
          </button>
          <button onClick={() => save('posted')} disabled={saving || readiness.blockers.length > 0}
            className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            Post Receipt
          </button>
        </>}
        {editDoc?.status === 'posted' && (
          <button onClick={doBounce} disabled={saving}
            className="px-3 py-1.5 border border-red-300 text-red-700 rounded text-sm hover:bg-red-50 font-medium">
            Mark Bounced
          </button>
        )}
      </div>

      {readiness.blockers.length > 0 && (
        <div className="px-5 py-3 border-b border-gray-100 bg-white">
          <SetupReadinessBanner readiness={readiness} />
        </div>
      )}

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
                    lines.filter(l => l.line_type === 'invoice_application').length === 0 ? 'No open invoices for this customer' :
                    `${lines.filter(l => l.line_type === 'invoice_application').length} open invoice${lines.filter(l => l.line_type === 'invoice_application').length !== 1 ? 's' : ''}`}
                </span>
              )}
            </div>
            {!fCustomer && !readOnly ? (
              <span className="text-xs text-gray-400">Select a customer to see open invoices</span>
            ) : !readOnly ? (
              <button onClick={addCustomerAdvanceLine}
                className="text-xs font-medium text-gray-500 hover:text-gray-900">
                + Add Customer Advance
              </button>
            ) : null}
          </div>

          {lines.length === 0 && !openInvoicesLoading ? (
            <div className="py-10 text-center text-sm text-gray-400">
              {fCustomer ? 'No open invoices found for this customer. Add a customer advance if money was received before invoicing.' : 'Select a customer above to load open invoices.'}
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['SI Number','SI Date','Original Amount','Balance Due','Payment Amount','CWT Base (net of VAT)','CWT (2307)','ATC Code','Forex Adj.','Remaining After'].map(h => (
                      <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap last:text-right">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {lines.map(l => {
                    const isAdvance = l.line_type === 'customer_advance'
                    const remaining = isAdvance ? 0 : l.balance_due - l.payment_amount - l.cwt_amount - l.forex_adjustment
                    const isOver = !isAdvance && l.payment_amount + l.cwt_amount > l.balance_due + 0.005
                    return (
                      <tr key={l._key} className={`hover:bg-gray-50 ${isOver ? 'bg-red-50/30' : ''}`}>
                        <td className="px-4 py-2.5 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">
                          <span>{l.si_number}</span>
                          {!readOnly && isAdvance && (
                            <button onClick={() => setLines(prev => prev.filter(row => row._key !== l._key))}
                              className="ml-2 text-[10px] font-sans font-medium text-gray-400 hover:text-red-600">
                              Remove
                            </button>
                          )}
                        </td>
                        <td className="px-4 py-2.5 text-xs text-gray-500 whitespace-nowrap">{isAdvance ? '—' : <DateCell date={l.si_date} />}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums text-gray-600">{isAdvance ? '—' : fmt(l.original_amount)}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{isAdvance ? '—' : fmt(l.balance_due)}</td>
                        <td className="px-4 py-2.5">
                          {readOnly ? (
                            <span className="font-mono text-xs tabular-nums text-gray-700">{fmt(l.payment_amount)}</span>
                          ) : (
                            <input type="number" min={0} step="any"
                              value={l.payment_amount || ''}
                              onChange={e => setLineField(l._key, 'payment_amount', parseFloat(e.target.value) || 0)}
                              className="w-28 border border-gray-300 rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900"
                              placeholder="0.00" />
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {readOnly ? (
                            <span className="font-mono text-xs tabular-nums text-gray-500">{l.cwt_amount > 0 ? fmt(l.cwt_tax_base) : '—'}</span>
                          ) : (
                            <input type="number" min={0} step="any"
                              value={l.cwt_tax_base || ''}
                              onChange={e => setLineField(l._key, 'cwt_tax_base', parseFloat(e.target.value) || 0)}
                              className="w-28 border border-gray-300 rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900"
                              placeholder="0.00" />
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {readOnly ? (
                            <span className="font-mono text-xs tabular-nums text-gray-500">{fmt(l.cwt_amount)}</span>
                          ) : (() => {
                            const atc = atcCodes.find(a => a.id === l.atc_code_id)
                            const expected = atc && l.cwt_tax_base > 0 ? round2(l.cwt_tax_base * atc.rate / 100) : null
                            const mismatch = expected !== null && l.cwt_amount > 0 && Math.abs(expected - l.cwt_amount) > 0.02
                            return (
                              <div>
                                <input type="number" min={0} step="any"
                                  value={l.cwt_amount || ''}
                                  onChange={e => setLineField(l._key, 'cwt_amount', parseFloat(e.target.value) || 0)}
                                  className={`w-24 border rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900 ${mismatch && !l.cwt_variance_reason ? 'border-amber-400 bg-amber-50/40' : 'border-gray-300'}`}
                                  placeholder="0.00" />
                                {mismatch && (
                                  <select
                                    value={l.cwt_variance_reason}
                                    onChange={e => setLineVarianceReason(l._key, e.target.value)}
                                    className="mt-1 w-24 border border-amber-300 rounded px-1 py-0.5 text-[10px] focus:outline-none"
                                    title={`Expected ${fmt(expected!)} at ${atc!.rate}% of ${fmt(l.cwt_tax_base)}`}>
                                    <option value="">Variance reason…</option>
                                    {CWT_VARIANCE_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
                                  </select>
                                )}
                              </div>
                            )
                          })()}
                        </td>
                        <td className="px-4 py-2.5">
                          {l.cwt_amount > 0 ? (
                            readOnly ? (
                              <span className="font-mono text-xs text-gray-600">
                                {atcCodes.find(a => a.id === l.atc_code_id)?.code || '—'}
                              </span>
                            ) : (
                              <select
                                value={l.atc_code_id || ''}
                                onChange={e => setLineAtc(l._key, e.target.value || null)}
                                className="w-28 border border-gray-300 rounded px-1.5 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                                <option value="">Select…</option>
                                {atcCodes.map(a => (
                                  <option key={a.id} value={a.id}>{a.code}</option>
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
                              onChange={e => setLineField(l._key, 'forex_adjustment', parseFloat(e.target.value) || 0)}
                              className="w-24 border border-gray-300 rounded px-2 py-1 text-xs text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900"
                              placeholder="0.00" />
                          )}
                        </td>
                        <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums ${remaining < -0.005 ? 'text-red-700 font-semibold' : 'text-gray-600'}`}>
                          {isAdvance ? '—' : fmt(Math.max(0, remaining))}
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

        <div className="px-5 py-4 bg-gray-50 border-t border-gray-100">
          <GLImpactPanel
            companyId={companyId}
            sourceDocType="OR"
            sourceDocId={editDoc?.id}
            previewRows={glImpactRows}
          />
        </div>

        {editDoc?.id && (
          <div className="px-5 py-4 bg-gray-50 border-t border-gray-100 space-y-3">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Audit Evidence</div>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                {auditFacts.map(fact => (
                  <div key={fact.label}>
                    <div className="text-[10px] uppercase tracking-wide text-gray-400 mb-1">{fact.label}</div>
                    <div className="text-xs font-medium text-gray-700">{fact.value}</div>
                  </div>
                ))}
              </div>
            </div>
            <AuditTrailSection tableName="receipts" recordId={editDoc.id} />
          </div>
        )}

        {editDoc?.posted_at && (
          <div className="bg-gray-50 px-5 py-3">
            <span className="text-xs text-gray-400">Posted {new Date(editDoc.posted_at).toLocaleString('en-PH')}</span>
          </div>
        )}
      </div>
    </div>
  )
}
