import { useState, useEffect, useCallback, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { composePhTin } from '@/lib/philippines'

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
      .select('id,si_number,date,total_amount,total_vat_amount,cwt_amount_expected,cwt_atc_code_id,cwt_tax_base')
      .eq('company_id', companyId).eq('customer_id', customerId)
      .eq('status', 'posted').order('date')
    if (!sis || sis.length === 0) { setLines([]); setOpenInvoicesLoading(false); return }

    // Get all applied amounts from receipt_lines (excluding current doc if editing)
    const siIds = sis.map(s => s.id)
    const { data: applied } = await supabase.from('receipt_lines')
      .select('invoice_id,payment_amount,cwt_amount,cwt_tax_base')
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

    const openLines: ApplicationLine[] = sis.map(si => {
      const totalPaid = (applied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.payment_amount) + Number(a.cwt_amount), 0)
      const totalAppliedCwt = (applied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.cwt_amount), 0)
      const totalAppliedCwtBase = (applied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.cwt_tax_base || 0), 0)
      const totalCM = (cmApplied || [])
        .filter(a => a.invoice_id === si.id)
        .reduce((s, a) => s + Number(a.total_amount), 0)
      const balance = Number(si.total_amount) - totalPaid - totalCM
      const invoiceExpectedCwt = Number(si.cwt_amount_expected || 0)
      const invoiceExpectedBase = Number(si.cwt_tax_base || 0)
      const invoiceAtcId = (si.cwt_atc_code_id as string | null) || null
      const effectiveAtcId = invoiceExpectedCwt > 0 ? invoiceAtcId : defaultAtcId
      const effectiveAtc = atcCodes.find(a => a.id === effectiveAtcId)
      // For CWT-enabled SIs, carry the SI's validated expected ATC/base into
      // receipts. Older SIs still fall back to customer-master defaults.
      const netRatio = Number(si.total_amount) > 0
        ? (Number(si.total_amount) - Number(si.total_vat_amount || 0)) / Number(si.total_amount)
        : 1
      const remainingExpectedCwt = invoiceExpectedCwt > 0
        ? Math.max(round2(invoiceExpectedCwt - totalAppliedCwt), 0)
        : null
      const remainingExpectedBase = invoiceExpectedBase > 0
        ? Math.max(round2(invoiceExpectedBase - totalAppliedCwtBase), 0)
        : null
      let defaultBase = 0
      let defaultCwt = 0
      if (effectiveAtc) {
        defaultBase = remainingExpectedBase !== null ? remainingExpectedBase : round2(balance * netRatio)
        defaultCwt = remainingExpectedCwt !== null
          ? Math.min(remainingExpectedCwt, balance)
          : round2(defaultBase * effectiveAtc.rate / 100)
      }
      return {
        _key: si.id,
        line_type: 'invoice_application' as const,
        invoice_id: si.id, si_number: si.si_number, si_date: si.date,
        original_amount: Number(si.total_amount), balance_due: balance,
        payment_amount: effectiveAtc ? round2(Math.max(balance - defaultCwt, 0)) : 0,
        cwt_amount: defaultCwt,
        forex_adjustment: 0,
        atc_code_id: effectiveAtcId,
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
    setFCustomerTIN(c ? composePhTin(c.tin, c.tin_branch_code) : '')
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
                    {['Receipt Date','Receipt Number','Reference','Customer','TIN','Payment Mode','Amount','CWT','Status'].map(h => (
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
                        <td className="px-4 py-2.5 font-mono text-xs text-gray-500 whitespace-nowrap">{r.reference_number || '—'}</td>
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

  // ── Form / View Workspace ─────────────────────────────────
  const selectedCustomer = customers.find(customer => customer.id === fCustomer)
  const selectedPaymentMode = paymentModes.find(paymentMode => paymentMode.id === fMode)
  const selectedBankAccount = bankAccounts.find(account => account.id === fBankAccount)
  const selectedBranch = branches.find(branch => branch.id === fBranch)
  const receiptStatus = editDoc?.status || 'draft'
  const workflowSteps = [{ key: 'draft', label: 'Draft' }, { key: 'posted', label: 'Posted' }, { key: 'bounced', label: 'Bounced' }, { key: 'cancelled', label: 'Voided' }]
  const validationErrors = [
    !fCustomer ? 'Customer is required.' : '',
    !fMode ? 'Payment mode is required.' : '',
    appliedLines.length === 0 ? 'At least one invoice application or customer advance is required.' : '',
    appliedLines.some(line => line.line_type === 'invoice_application' && line.payment_amount + line.cwt_amount > line.balance_due + 0.005) ? 'An application exceeds the invoice open balance.' : '',
    appliedLines.some(line => line.cwt_amount > 0 && !line.atc_code_id) ? 'ATC code is required for every CWT amount.' : '',
    appliedLines.some(line => line.cwt_amount > 0 && line.cwt_tax_base <= 0) ? 'CWT tax base must be greater than zero.' : '',
  ].filter(Boolean)

  return (
    <TransactionWorkspace
      title="Official Receipt"
      documentNo={editDoc?.receipt_number}
      status={receiptStatus}
      statusLabel={receiptStatus}
      family="sales"
      identity={{ name: fCustomerName || selectedCustomer?.registered_name || 'Customer not selected', secondary: fCustomerTIN || undefined }}
      metrics={[
        { label: 'Cash Received', value: `₱${fmt(totalPayment)}`, emphasis: true },
        { label: 'CWT', value: `₱${fmt(totalCWT)}` },
        { label: 'Total Applied', value: `₱${fmt(totalPayment + totalCWT)}`, emphasis: true },
      ]}
      meta={[
        { label: 'Mode', value: readOnly ? 'Read only' : 'Editable', tone: readOnly ? 'warning' : 'info' },
        { label: 'Posting', value: editDoc?.posted_at ? 'Posted' : 'Not posted', tone: editDoc?.posted_at ? 'success' : 'neutral' },
      ]}
      actions={[
        ...(canEdit ? [
          { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: () => save('draft'), disabled: saving || readiness.blockers.length > 0 },
          { key: 'post', label: saving ? 'Posting…' : 'Post Receipt', onClick: () => save('posted'), disabled: saving || readiness.blockers.length > 0, variant: 'primary' as const },
        ] : []),
        ...(editDoc?.status === 'posted' ? [{ key: 'bounce', label: 'Mark Bounced', onClick: doBounce, disabled: saving, variant: 'danger' as const, group: 'more' as const }] : []),
      ]}
      workflow={{ steps: workflowSteps, currentKey: receiptStatus }}
      cards={[
        { title: 'Document Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className={lbl}>Receipt Date<input type="date" value={fDate} onChange={event => setFDate(event.target.value)} disabled={readOnly} className={`${readOnly ? ro : inp} mt-1`} /></label><label className={lbl}>Branch<select value={fBranch} onChange={event => setFBranch(event.target.value)} disabled={readOnly} className={`${readOnly ? ro : inp} mt-1`}><option value="">Select branch…</option>{branches.map(branch => <option key={branch.id} value={branch.id}>{branch.branch_code} – {branch.branch_name}</option>)}</select></label><div><div className="pxl-field-label">Receipt Number</div><div className="pxl-body-text mt-1 font-mono">{editDoc?.receipt_number || 'Generated on save'}</div></div><div><div className="pxl-field-label">Lock State</div><div className="pxl-body-text mt-1">{receiptStatus === 'draft' ? 'Editable draft' : 'Lifecycle controlled'}</div></div></div> },
        { title: 'Customer Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className={`${lbl} sm:col-span-2`}>Customer{readOnly ? <div className={`${ro} mt-1`}>{fCustomerName}</div> : <select value={fCustomer} onChange={event => onCustomerChange(event.target.value)} className={`${inp} mt-1`}><option value="">Select customer…</option>{customers.map(customer => <option key={customer.id} value={customer.id}>{customer.registered_name}</option>)}</select>}</label><div><div className="pxl-field-label">Customer TIN</div><div className="pxl-body-text mt-1 font-mono">{fCustomerTIN || '—'}</div></div><div><div className="pxl-field-label">CWT Profile</div><div className="pxl-body-text mt-1">{selectedCustomer?.is_subject_to_cwt ? 'Subject to CWT' : 'Not subject / snapshot only'}</div></div></div> },
        { title: 'Payment Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className={lbl}>Payment Mode{readOnly ? <div className={`${ro} mt-1`}>{selectedPaymentMode?.name || '—'}</div> : <select value={fMode} onChange={event => setFMode(event.target.value)} className={`${inp} mt-1`}><option value="">Select mode…</option>{paymentModes.map(paymentMode => <option key={paymentMode.id} value={paymentMode.id}>{paymentMode.name}</option>)}</select>}</label><label className={lbl}>Reference / Check #{readOnly ? <div className={`${ro} mt-1`}>{fRef || '—'}</div> : <input value={fRef} onChange={event => setFRef(event.target.value)} className={`${inp} mt-1`} />}</label><label className={`${lbl} sm:col-span-2`}>Deposit Account{readOnly ? <div className={`${ro} mt-1`}>{selectedBankAccount ? `${selectedBankAccount.account_code} – ${selectedBankAccount.account_name}` : '—'}</div> : <select value={fBankAccount} onChange={event => setFBankAccount(event.target.value)} className={`${inp} mt-1`}><option value="">Select account…</option>{bankAccounts.map(account => <option key={account.id} value={account.id}>{account.account_code} – {account.account_name}</option>)}</select>}</label></div> },
      ]}
      tabBadges={{ lines: lines.length }}
      tabContent={{
        lines: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]"><div className="flex items-center justify-between border-b border-[var(--pxl-border-medium)] px-3 py-2"><div><h2 className="pxl-section-title">Applications & Advances</h2>{openInvoicesLoading && <span className="pxl-caption">Loading open invoices…</span>}</div>{!readOnly && fCustomer && <button onClick={addCustomerAdvanceLine} className="pxl-button pxl-button--text">+ Add Customer Advance</button>}</div>{lines.length === 0 ? <TransactionEmptyState>{fCustomer ? 'No open invoices found. Add a customer advance when applicable.' : 'Select a customer to load open invoices.'}</TransactionEmptyState> : <table className="pxl-data-grid w-full text-xs"><thead><tr>{['Source Document', 'Date', 'Original', 'Open Balance', 'Payment', 'CWT Base', 'CWT', 'ATC', 'Forex', 'Remaining'].map(label => <th key={label} className={['Original', 'Open Balance', 'Payment', 'CWT Base', 'CWT', 'Forex', 'Remaining'].includes(label) ? 'text-right' : 'text-left'}>{label}</th>)}</tr></thead><tbody>{lines.map(line => { const isAdvance = line.line_type === 'customer_advance'; const remaining = isAdvance ? 0 : line.balance_due - line.payment_amount - line.cwt_amount - line.forex_adjustment; const atc = atcCodes.find(code => code.id === line.atc_code_id); const expected = atc && line.cwt_tax_base > 0 ? round2(line.cwt_tax_base * atc.rate / 100) : null; const mismatch = expected !== null && line.cwt_amount > 0 && Math.abs(expected - line.cwt_amount) > 0.02; return <tr key={line._key}><td className="font-mono font-semibold">{line.si_number}{!readOnly && isAdvance && <button onClick={() => setLines(current => current.filter(row => row._key !== line._key))} className="ml-2 text-red-600">Remove</button>}</td><td>{isAdvance ? '—' : <DateCell date={line.si_date} />}</td><td className="text-right font-mono">{isAdvance ? '—' : fmt(line.original_amount)}</td><td className="text-right font-mono">{isAdvance ? '—' : fmt(line.balance_due)}</td><td className="text-right">{readOnly ? <span className="font-mono">{fmt(line.payment_amount)}</span> : <input type="number" min={0} value={line.payment_amount || ''} onChange={event => setLineField(line._key, 'payment_amount', Number(event.target.value) || 0)} className="w-24 rounded border px-2 py-1 text-right font-mono" />}</td><td className="text-right">{readOnly ? <span className="font-mono">{line.cwt_amount > 0 ? fmt(line.cwt_tax_base) : '—'}</span> : <input type="number" min={0} value={line.cwt_tax_base || ''} onChange={event => setLineField(line._key, 'cwt_tax_base', Number(event.target.value) || 0)} className="w-24 rounded border px-2 py-1 text-right font-mono" />}</td><td className="text-right">{readOnly ? <span className="font-mono">{fmt(line.cwt_amount)}</span> : <div><input type="number" min={0} value={line.cwt_amount || ''} onChange={event => setLineField(line._key, 'cwt_amount', Number(event.target.value) || 0)} className={`w-20 rounded border px-2 py-1 text-right font-mono ${mismatch && !line.cwt_variance_reason ? 'border-amber-400 bg-amber-50' : ''}`} />{mismatch && <select value={line.cwt_variance_reason} onChange={event => setLineVarianceReason(line._key, event.target.value)} className="mt-1 w-24 rounded border border-amber-300 text-[10px]"><option value="">Variance…</option>{CWT_VARIANCE_REASONS.map(reasonItem => <option key={reasonItem.value} value={reasonItem.value}>{reasonItem.label}</option>)}</select>}</div>}</td><td>{line.cwt_amount > 0 ? readOnly ? atc?.code || '—' : <select value={line.atc_code_id || ''} onChange={event => setLineAtc(line._key, event.target.value || null)} className="w-24 rounded border px-1.5 py-1"><option value="">Select…</option>{atcCodes.map(code => <option key={code.id} value={code.id}>{code.code}</option>)}</select> : '—'}</td><td className="text-right">{readOnly ? <span className="font-mono">{fmt(line.forex_adjustment)}</span> : <input type="number" value={line.forex_adjustment || ''} onChange={event => setLineField(line._key, 'forex_adjustment', Number(event.target.value) || 0)} className="w-20 rounded border px-2 py-1 text-right font-mono" />}</td><td className={`text-right font-mono ${remaining < -0.005 ? 'text-red-700' : ''}`}>{isAdvance ? '—' : fmt(Math.max(remaining, 0))}</td></tr>})}</tbody></table>}</div>,
        financial: <div className="ml-auto grid max-w-lg grid-cols-2 gap-2"><span className="text-gray-600">Payment Amount</span><span className="text-right font-mono">₱{fmt(totalPayment)}</span><span className="text-gray-600">CWT Applied</span><span className="text-right font-mono">₱{fmt(totalCWT)}</span><span className="text-gray-600">Applied Amount</span><span className="text-right font-mono">₱{fmt(totalPayment + totalCWT)}</span><span className="text-gray-600">Customer Advance</span><span className="text-right font-mono">₱{fmt(advanceGross)}</span><span className="pxl-section-title border-t pt-2">Cash / Bank Amount</span><span className="border-t pt-2 text-right font-mono font-bold">₱{fmt(totalPayment)}</span></div>,
        gl: <GLImpactPanel companyId={companyId} sourceDocType="OR" sourceDocId={editDoc?.id} previewRows={glImpactRows} />,
        tax: appliedLines.some(line => line.cwt_amount > 0) ? <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]"><table className="pxl-data-grid w-full"><thead><tr>{['Source Document', 'ATC', 'CWT Base', 'Rate', 'CWT Amount', 'Timing'].map(label => <th key={label} className={['CWT Base', 'Rate', 'CWT Amount'].includes(label) ? 'text-right' : 'text-left'}>{label}</th>)}</tr></thead><tbody>{appliedLines.filter(line => line.cwt_amount > 0).map(line => { const atc = atcCodes.find(code => code.id === line.atc_code_id); return <tr key={line._key}><td className="font-mono">{line.si_number}</td><td>{atc?.code || 'Missing'}</td><td className="text-right font-mono">₱{fmt(line.cwt_tax_base)}</td><td className="text-right font-mono">{atc ? `${atc.rate}%` : '—'}</td><td className="text-right font-mono">₱{fmt(line.cwt_amount)}</td><td>Recognized on receipt posting</td></tr>})}</tbody></table></div> : <TransactionEmptyState>No CWT is applied to this Official Receipt.</TransactionEmptyState>,
        validation: <div className="space-y-2">{readiness.blockers.length > 0 && <SetupReadinessBanner readiness={readiness} />}{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{validationErrors.length > 0 ? validationErrors.map(message => <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Receipt applications, tax data, and posting references are ready.</div>}</div>,
        workflow: <ol className="grid gap-2 sm:grid-cols-4">{workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === receiptStatus ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
        approval: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Approval Status</div><div className="pxl-body-text mt-1">{receiptStatus === 'draft' ? 'Posting authorization required' : receiptStatus === 'posted' ? 'Posting completed' : receiptStatus}</div></div><div><div className="pxl-field-label">Control</div><div className="pxl-body-text mt-1">Permission, period, and setup readiness</div></div><div><div className="pxl-field-label">Next Action</div><div className="pxl-body-text mt-1">{receiptStatus === 'draft' ? 'Post Receipt' : receiptStatus === 'posted' ? 'Mark Bounced when applicable' : 'No action available'}</div></div></div>,
        audit: editDoc?.id ? <div className="space-y-4"><div className="grid gap-3 sm:grid-cols-4">{auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div><AuditTrailSection tableName="receipts" recordId={editDoc.id} /></div> : <TransactionEmptyState>Audit history begins after the Official Receipt is saved.</TransactionEmptyState>,
        related: appliedLines.some(line => line.invoice_id) ? <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]"><table className="pxl-data-grid w-full"><thead><tr><th className="text-left">Relationship</th><th className="text-left">Document</th><th className="text-right">Applied</th><th className="text-left">Open</th></tr></thead><tbody>{appliedLines.filter(line => line.invoice_id).map(line => <tr key={line._key}><td>Applies to</td><td className="font-mono font-semibold">{line.si_number}</td><td className="text-right font-mono">₱{fmt(line.payment_amount + line.cwt_amount)}</td><td><Link to={`/sales-invoices/${line.invoice_id}`} className="text-blue-700 hover:underline">Sales Invoice</Link></td></tr>)}</tbody></table></div> : <TransactionEmptyState>No Sales Invoice is linked; the receipt contains customer-advance content only.</TransactionEmptyState>,
        party: selectedCustomer ? <dl className="grid gap-3 sm:grid-cols-3"><div><dt className="pxl-field-label">Customer</dt><dd className="pxl-body-text mt-1">{selectedCustomer.registered_name}</dd></div><div><dt className="pxl-field-label">TIN</dt><dd className="pxl-body-text mt-1 font-mono">{composePhTin(selectedCustomer.tin, selectedCustomer.tin_branch_code)}</dd></div><div><dt className="pxl-field-label">Registered Address</dt><dd className="pxl-body-text mt-1">{selectedCustomer.registered_address || '—'}</dd></div></dl> : <TransactionEmptyState>Select a customer to see related-party information.</TransactionEmptyState>,
        activity: <div className="grid gap-3 sm:grid-cols-4">{auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div>,
        notes: <label className={lbl}>Receipt Remarks<textarea value={fRemarks} onChange={event => setFRemarks(event.target.value)} disabled={readOnly} rows={5} className={`${readOnly ? ro : inp} mt-1 resize-none`} /></label>,
        system: <SystemMetadataPanel facts={[
          { label: 'Internal ID', value: editDoc?.id || 'Assigned when saved', hint: 'Transaction identity' },
          { label: 'Document Number', value: editDoc?.receipt_number || 'Generated from number series', hint: 'Official Receipt number' },
          { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
          { label: 'Branch', value: selectedBranch ? `${selectedBranch.branch_code} — ${selectedBranch.branch_name}` : fBranch || '—', hint: 'Posting context' },
          { label: 'Payment Mode', value: selectedPaymentMode?.name || 'Not selected', hint: 'Settlement method' },
          { label: 'Bank / Cash Account', value: selectedBankAccount ? `${selectedBankAccount.account_code} — ${selectedBankAccount.account_name}` : 'Default cash account', hint: 'Posting source' },
          { label: 'Created', value: formatDateTime(editDoc?.created_at), hint: 'Audit metadata' },
          { label: 'Updated', value: formatDateTime(editDoc?.updated_at), hint: 'Audit metadata' },
          { label: 'Posted', value: formatDateTime(editDoc?.posted_at), hint: 'Lifecycle metadata' },
        ]} />,
      }}
      emptyTabMessages={{ attachments: 'No attachments have been added to this Official Receipt.' }}
      sidebarPanels={[
        { key: 'application', title: 'Application Summary', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Applied</span><span className="font-mono text-xs">₱{fmt(totalPayment + totalCWT)}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Advance</span><span className="font-mono text-xs">₱{fmt(advanceGross)}</span></div></div> },
        { key: 'payment', title: 'Payment', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Cash Received</span><span className="font-mono text-sm font-bold">₱{fmt(totalPayment)}</span></div><div className="pxl-caption">{selectedPaymentMode?.name || 'Payment mode not selected'}</div></div> },
        { key: 'tax', title: 'Tax', content: <div className="flex justify-between gap-3"><span className="pxl-field-label">CWT</span><span className="font-mono text-xs">₱{fmt(totalCWT)}</span></div> },
        { key: 'gl', title: 'GL Preview', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Debit</span><span className="font-mono text-xs">₱{fmt(glImpactRows.reduce((sum, row) => sum + row.debit, 0))}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Credit</span><span className="font-mono text-xs">₱{fmt(glImpactRows.reduce((sum, row) => sum + row.credit, 0))}</span></div></div> },
        { key: 'customer', title: 'Customer', content: <div><div className="text-xs font-semibold">{fCustomerName || selectedCustomer?.registered_name || 'Not selected'}</div><div className="pxl-caption mt-1 font-mono">{fCustomerTIN || 'No TIN'}</div></div> },
      ]}
      footer={<span>Created {formatDateTime(editDoc?.created_at)} · Updated {formatDateTime(editDoc?.updated_at)} · {receiptStatus === 'draft' ? 'Editable draft' : 'Frozen by lifecycle controls'}</span>}
      onBack={() => setMode('list')}
      backLabel="Receipts"
    />
  )
}
