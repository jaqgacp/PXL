import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge } from '@/components/ui/shared'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'

// ── Types ─────────────────────────────────────────────────────
type PVStatus = 'draft' | 'posted' | 'cancelled'

type PV = {
  id: string; company_id: string; branch_id: string
  supplier_id: string; supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  voucher_number: string; voucher_date: string
  payment_mode_id: string | null; reference_number: string | null
  bank_account_id: string | null; total_amount: number; total_ewt: number
  remarks: string | null; status: PVStatus
  posted_at: string | null; approved_at?: string | null; updated_at?: string | null; created_at: string
}

type PVLine = {
  _key: string; id?: string
  vendor_bill_id: string
  bill_number: string; bill_total: number; bill_outstanding: number
  bill_net_base: number
  payment_amount: number; ewt_amount: number; atc_code_id: string
  ewt_tax_base: number; ewt_income_nature: string; ewt_variance_reason: string
}

type SupplierRef = {
  id: string
  registered_name: string
  tin: string
  is_subject_to_ewt: boolean
  default_atc_code_id: string | null
}
type VendorBillRef = {
  id: string; bill_number: string; total_amount: number; outstanding: number
  net_base: number
  bill_date: string; supplier_invoice_number: string | null
}
type COARef = { id: string; account_code: string; account_name: string }
type PaymentMode = { id: string; code: string; name: string }
type ATCCode = { id: string; code: string; description: string; rate: number }
type Branch = { id: string; branch_code: string; branch_name: string }

const PV_REQUIRED_CONFIG: ConfigField[] = ['ap_account_id', 'default_cash_account_id', 'ewt_payable_account_id']
const EWT_VARIANCE_REASONS = [
  { value: 'rounding', label: 'Rounding' },
  { value: 'partial_non_taxable', label: 'Partial non-taxable' },
  { value: 'bir_ruling', label: 'BIR ruling' },
  { value: 'supplier_exempt', label: 'Supplier exempt' },
  { value: 'other_authorized', label: 'Other authorized' },
]

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]
const round2 = (n: number) => Math.round(n * 100) / 100

const newLine = (): PVLine => ({
  _key: crypto.randomUUID(), vendor_bill_id: '', bill_number: '', bill_total: 0,
  bill_outstanding: 0, bill_net_base: 0, payment_amount: 0, ewt_amount: 0, atc_code_id: '',
  ewt_tax_base: 0, ewt_income_nature: '', ewt_variance_reason: '',
})

const proportionalNetBase = (grossPortion: number, grossTotal: number, netBase: number) => {
  if (grossPortion <= 0 || grossTotal <= 0 || netBase <= 0) return 0
  return round2(Math.min(netBase, (grossPortion / grossTotal) * netBase))
}

const formatDateTime = (value?: string | null) => {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

// ── Component ─────────────────────────────────────────────────
export default function PaymentVouchersPage() {
  const { companyId, branchId } = useAppCtx()

  const [vouchers, setVouchers] = useState<PV[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editPV, setEditPV] = useState<Partial<PV> | null>(null)
  const [lines, setLines] = useState<PVLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [openBills, setOpenBills] = useState<VendorBillRef[]>([])
  const [cashAccounts, setCashAccounts] = useState<COARef[]>([])
  const [paymentModes, setPaymentModes] = useState<PaymentMode[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const [voiding, setVoiding] = useState(false)

  const readOnly = mode === 'view'
  const readiness = useTransactionReadiness({
    companyId,
    branchId: mode === 'list' ? branchId : (editPV?.branch_id || branchId || ''),
    documentCode: 'PV',
    postingDate: editPV?.voucher_date || today(),
    requiredConfig: PV_REQUIRED_CONFIG,
  })

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('payment_vouchers').select('*')
      .eq('company_id', companyId).order('voucher_date', { ascending: false }).order('voucher_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    const { data } = await q
    setVouchers(data as PV[] || [])
    setLoading(false)
  }, [companyId, fStatus])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [suppRes, coaRes, pmRes, atcRes, brRes] = await Promise.all([
      supabase.from('suppliers').select('id,registered_name,tin,is_subject_to_ewt,default_atc_code_id').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).in('account_type', ['asset']).order('account_code'),
      supabase.from('ref_payment_modes').select('id,code,name').eq('is_active', true).order('sort_order'),
      supabase.from('atc_codes').select('id,code,description,rate').eq('is_active', true).eq('tax_category', 'ewt').order('code'),
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true),
    ])
    setSuppliers(suppRes.data as SupplierRef[] || [])
    setCashAccounts(coaRes.data as COARef[] || [])
    setPaymentModes(pmRes.data as PaymentMode[] || [])
    setAtcCodes(atcRes.data as ATCCode[] || [])
    setBranches(brRes.data as Branch[] || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])
  useEffect(() => { if (companyId) load() }, [load, fStatus, companyId])

  // Load open bills for a supplier (posted, not fully paid)
  const loadOpenBills = useCallback(async (supplierId: string) => {
    if (!companyId || !supplierId) { setOpenBills([]); return }
    const { data: billsData } = await supabase
      .from('vendor_bills')
      .select('id,bill_number,total_amount,total_input_vat_amount,total_taxable_amount,total_zero_rated_amount,total_exempt_amount,bill_date,supplier_invoice_number')
      .eq('company_id', companyId).eq('supplier_id', supplierId)
      .in('status', ['posted'])
      .order('bill_date')

    if (!billsData || billsData.length === 0) { setOpenBills([]); return }

    // Get payments already applied
    const billIds = billsData.map((b: any) => b.id)
    const { data: pvlData } = await supabase
      .from('payment_voucher_lines')
      .select('vendor_bill_id,payment_amount,ewt_amount,payment_vouchers(status)')
      .in('vendor_bill_id', billIds)

    const paidMap: Record<string, number> = {}
    for (const pvl of pvlData || []) {
      if ((pvl as any).payment_vouchers?.status === 'cancelled') continue
      const k = (pvl as any).vendor_bill_id
      paidMap[k] = (paidMap[k] || 0) + Number((pvl as any).payment_amount) + Number((pvl as any).ewt_amount)
    }

    const result: VendorBillRef[] = (billsData as any[])
      .map(b => {
        const total = Number(b.total_amount)
        const outstanding = Math.max(total - (paidMap[b.id] || 0), 0)
        const netBase = Number(b.total_taxable_amount || 0) + Number(b.total_zero_rated_amount || 0) + Number(b.total_exempt_amount || 0)
        const fallbackNetBase = Math.max(total - Number(b.total_input_vat_amount || 0), 0)
        return {
          id: b.id,
          bill_number: b.bill_number,
          total_amount: total,
          outstanding,
          net_base: netBase > 0 ? netBase : fallbackNetBase,
          bill_date: b.bill_date,
          supplier_invoice_number: b.supplier_invoice_number,
        }
      })
      .filter(b => b.outstanding > 0.01)

    setOpenBills(result)
  }, [companyId])

  const openNew = () => {
    if (readiness.blockers.length > 0) {
      setError('Complete company, branch, fiscal period, number series, and GL posting setup before creating a payment voucher.')
      return
    }
    setEditPV({ company_id: companyId!, branch_id: branchId || '', voucher_date: today(), status: 'draft' })
    setLines([newLine()])
    setOpenBills([])
    setError('')
    setMode('edit')
  }

  const openView = (pv: PV) => {
    setEditPV(pv)
    supabase.from('payment_voucher_lines')
      .select('*,vendor_bills(bill_number,total_amount)')
      .eq('payment_voucher_id', pv.id)
      .then(({ data }) => {
        const mapped: PVLine[] = (data || []).map((l: any) => ({
          _key: l.id, id: l.id,
          vendor_bill_id: l.vendor_bill_id || '',
          bill_number: l.vendor_bills?.bill_number || '',
          bill_total: Number(l.vendor_bills?.total_amount || 0),
          bill_outstanding: 0,
          bill_net_base: 0,
          payment_amount: Number(l.payment_amount),
          ewt_amount: Number(l.ewt_amount),
          atc_code_id: l.atc_code_id || '',
          ewt_tax_base: Number(l.ewt_tax_base || 0),
          ewt_income_nature: l.ewt_income_nature || '',
          ewt_variance_reason: l.ewt_variance_reason || '',
        }))
        setLines(mapped.length > 0 ? mapped : [newLine()])
      })
    setError('')
    setMode(pv.status === 'draft' ? 'edit' : 'view')
  }

  const pickSupplier = async (id: string) => {
    const s = suppliers.find(x => x.id === id)
    if (!s) return
    setEditPV(v => ({ ...v, supplier_id: id, supplier_name_snapshot: s.registered_name, supplier_tin_snapshot: s.tin }))
    setLines([newLine()])
    await loadOpenBills(id)
  }

  const pickBill = (lineKey: string, billId: string) => {
    const bill = openBills.find(b => b.id === billId)
    if (!bill) {
      setLines(ls => ls.map(l => l._key !== lineKey ? l : { ...l, vendor_bill_id: '', bill_number: '', bill_total: 0, bill_outstanding: 0, bill_net_base: 0, payment_amount: 0 }))
      return
    }
    const supplier = suppliers.find(s => s.id === editPV?.supplier_id)
    const defaultAtc = supplier?.is_subject_to_ewt ? supplier.default_atc_code_id || '' : ''
    const defaultTaxBase = proportionalNetBase(bill.outstanding, bill.total_amount, bill.net_base)
    setLines(ls => ls.map(l => l._key !== lineKey ? l : recalcLineEwt(l, {
      vendor_bill_id: bill.id, bill_number: bill.bill_number,
      bill_total: bill.total_amount, bill_outstanding: bill.outstanding, bill_net_base: bill.net_base,
      payment_amount: bill.outstanding, ewt_amount: 0,
      ewt_tax_base: l.ewt_tax_base || defaultTaxBase,
      atc_code_id: l.atc_code_id || defaultAtc,
    })))
  }

  const recalcLineEwt = (line: PVLine, patch: Partial<PVLine>) => {
    const next = { ...line, ...patch }
    const atc = atcCodes.find(a => a.id === next.atc_code_id)
    if (!atc || atc.rate <= 0) {
      return { ...next, ewt_amount: 0, atc_code_id: next.atc_code_id || '', ewt_income_nature: '' }
    }

    if (patch.atc_code_id !== undefined || patch.vendor_bill_id !== undefined || patch.ewt_tax_base !== undefined) {
      const gross = next.bill_outstanding || next.payment_amount + next.ewt_amount
      const base = next.ewt_tax_base || gross
      const ewt = round2(base * atc.rate / 100)
      return {
        ...next,
        ewt_tax_base: base,
        ewt_amount: ewt,
        payment_amount: next.bill_outstanding ? round2(Math.max(gross - ewt, 0)) : next.payment_amount,
        ewt_income_nature: next.ewt_income_nature || atc.description,
        ewt_variance_reason: '',
      }
    }

    if (patch.payment_amount !== undefined) {
      const gross = round2(next.payment_amount + next.ewt_amount)
      const base = next.ewt_tax_base || gross
      const ewt = round2(base * atc.rate / 100)
      return { ...next, ewt_tax_base: base, ewt_amount: ewt, ewt_variance_reason: '' }
    }

    return next
  }

  const updateLine = (key: string, field: keyof PVLine, raw: string) => {
    setLines(ls => ls.map(l => {
      if (l._key !== key) return l
      const value = ['payment_amount','ewt_amount','ewt_tax_base'].includes(field) ? parseFloat(raw) || 0 : raw
      return recalcLineEwt(l, { [field]: value } as Partial<PVLine>)
    }))
  }

  const totalPayment = lines.reduce((s, l) => s + l.payment_amount, 0)
  const totalEWT     = lines.reduce((s, l) => s + l.ewt_amount, 0)
  const glImpactRows: GLImpactRow[] = [
    { configKey: 'ap_account_id', description: 'Accounts payable cleared', debit: totalPayment + totalEWT, credit: 0 },
    {
      accountId: editPV?.bank_account_id || null,
      configKey: editPV?.bank_account_id ? undefined : 'default_cash_account_id',
      description: 'Cash paid',
      debit: 0,
      credit: totalPayment,
    },
    { configKey: 'ewt_payable_account_id', description: 'EWT payable', debit: 0, credit: totalEWT },
  ]

  const save = async (post: boolean) => {
    if (!companyId || !editPV) return
    if (!editPV.supplier_id) { setError('Please select a supplier'); return }
    if (readiness.blockers.length > 0) {
      setError('Complete setup readiness blockers before saving or posting this payment voucher.')
      return
    }
    for (const line of lines.filter(l => l.payment_amount > 0 || l.ewt_amount > 0)) {
      if (line.ewt_amount > 0 && !line.atc_code_id) {
        setError('ATC code is required when EWT is withheld.')
        return
      }
      const atc = atcCodes.find(a => a.id === line.atc_code_id)
      if (line.ewt_amount > 0 && atc) {
        if (line.ewt_tax_base <= 0) {
          setError(`EWT taxable base is required for ${line.bill_number || 'selected bill'}.`)
          return
        }
        if (!line.ewt_income_nature.trim()) {
          setError(`Income nature is required for ${line.bill_number || 'selected bill'}.`)
          return
        }
        const expected = round2(line.ewt_tax_base * atc.rate / 100)
        if (Math.abs(expected - line.ewt_amount) > 0.02 && !line.ewt_variance_reason) {
          setError(`EWT for ${line.bill_number || 'selected bill'} should be ${fmt(expected)} for ATC ${atc.code}, or a variance reason is required.`)
          return
        }
      }
    }
    setSaving(true); setError('')
    try {
      const header = {
        company_id: companyId, branch_id: editPV.branch_id || branchId || '',
        supplier_id: editPV.supplier_id,
        supplier_name_snapshot: editPV.supplier_name_snapshot || '',
        supplier_tin_snapshot: editPV.supplier_tin_snapshot || '',
        voucher_date: editPV.voucher_date || today(),
        payment_mode_id: editPV.payment_mode_id || '',
        reference_number: editPV.reference_number || '',
        bank_account_id: editPV.bank_account_id || '',
        total_amount: totalPayment.toString(),
        total_ewt: totalEWT.toString(),
        remarks: editPV.remarks || '',
      }
      const linesPayload = lines
        .filter(l => l.payment_amount > 0)
        .map(l => ({
          vendor_bill_id: l.vendor_bill_id || null,
          payment_amount: l.payment_amount,
          ewt_amount: l.ewt_amount,
          atc_code_id: l.atc_code_id || null,
          ewt_tax_base: l.ewt_tax_base || null,
          ewt_income_nature: l.ewt_income_nature || null,
          ewt_variance_reason: l.ewt_variance_reason || null,
        }))

      const { data: pvId, error: saveErr } = await supabase.rpc('fn_save_payment_voucher', {
        p_voucher_id: (editPV.id || null)!, p_header: header, p_lines: linesPayload,
      })
      if (saveErr) throw saveErr

      if (post) {
        const { error: postErr } = await supabase.rpc('fn_post_payment_voucher', { p_voucher_id: pvId })
        if (postErr) throw postErr
      }

      await load()
      setMode('list')
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally {
      setSaving(false)
    }
  }

  const voidVoucher = async () => {
    if (!editPV?.id) return
    if (!confirm(`Void payment voucher ${editPV.voucher_number}? This will create a reversing journal entry.`)) return
    setVoiding(true); setError('')
    try {
      const { error: e } = await supabase.rpc('fn_cancel_payment_voucher', { p_voucher_id: editPV.id })
      if (e) throw e
      await load(); setMode('list')
    } catch (e: any) {
      setError(e.message || 'Void failed')
    } finally { setVoiding(false) }
  }

  const filtered = vouchers.filter(v =>
    !fSearch || v.voucher_number.includes(fSearch) ||
    v.supplier_name_snapshot.toLowerCase().includes(fSearch.toLowerCase())
  )

  // ── List View ─────────────────────────────────────────────────
  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Payment Vouchers</span>
        <input value={fSearch} onChange={e => setFSearch(e.target.value)} placeholder="Search voucher # / supplier…"
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-52 focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="posted">Posted</option>
          <option value="cancelled">Void</option>
        </select>
        <button onClick={openNew} disabled={readiness.loading || readiness.blockers.length > 0}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed">
          + New Payment Voucher
        </button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>

      {companyId && readiness.blockers.length > 0 && (
        <div className="px-5 py-3 border-b border-gray-100">
          <SetupReadinessBanner readiness={readiness} />
        </div>
      )}

      {loading ? (
        <div className="divide-y divide-gray-100">{[...Array(5)].map((_, i) => (
          <div key={i} className="px-5 py-3 flex gap-4 animate-pulse">
            <div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" />
          </div>
        ))}</div>
      ) : filtered.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No payment vouchers</p>
          <p className="text-xs text-gray-400 mt-1">Create a payment voucher to record a supplier payment.</p>
        </div>
      ) : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              {['Voucher #','Date','Supplier','Reference','Cash Paid','EWT','Total Applied','Status'].map(h => (
                <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Cash Paid','EWT','Total Applied'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {filtered.map(pv => (
              <tr key={pv.id} onClick={() => openView(pv)}
                className={`cursor-pointer hover:bg-gray-50/60 ${pv.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900">{pv.voucher_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{pv.voucher_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-900 max-w-[160px] truncate">{pv.supplier_name_snapshot}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{pv.reference_number || '—'}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(pv.total_amount)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-blue-600">{fmt(pv.total_ewt)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(pv.total_amount + pv.total_ewt)}</td>
                <td className="px-3 py-2.5"><StatusBadge status={pv.status} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )

  // ── Edit / View ───────────────────────────────────────────────
  const h = (label: string, children: React.ReactNode) => (
    <div className="flex flex-col gap-1">
      <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>
      {children}
    </div>
  )
  const inputCls = `border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50 disabled:text-gray-500 w-full`
  const auditFacts = [
    { label: 'Created', value: formatDateTime(editPV?.created_at) },
    { label: 'Last edited', value: formatDateTime(editPV?.updated_at) },
    { label: 'Approved', value: formatDateTime(editPV?.approved_at) },
    { label: 'Posted', value: formatDateTime(editPV?.posted_at) },
    { label: 'Lock status', value: editPV?.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ]

  return (
    <div className="flex flex-col h-full">
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2 flex-wrap">
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-semibold text-gray-700">{editPV?.voucher_number || 'New Payment Voucher'}</span>
        {editPV?.status && <StatusBadge status={editPV.status} />}
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          {!readOnly && (
            <>
              <button onClick={() => save(false)} disabled={saving || readiness.blockers.length > 0}
                className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50 disabled:opacity-50">
                {saving ? 'Saving…' : 'Save Draft'}
              </button>
              <button onClick={() => save(true)} disabled={saving || readiness.blockers.length > 0}
                className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
                {saving ? 'Posting…' : 'Save & Post'}
              </button>
            </>
          )}
          {readOnly && editPV?.status === 'posted' && (
            <button onClick={voidVoucher} disabled={voiding}
              className="px-3 py-1.5 border border-red-300 text-red-600 rounded text-sm hover:bg-red-50 disabled:opacity-50">
              {voiding ? 'Voiding…' : 'Void'}
            </button>
          )}
        </div>
      </div>

      {readiness.blockers.length > 0 && (
        <div className="px-5 py-3 border-b border-gray-100 bg-white">
          <SetupReadinessBanner readiness={readiness} />
        </div>
      )}

      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        {/* Header */}
        <div className="bg-white border border-gray-200 rounded-lg p-5 mb-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            {h('Supplier', (
              <select value={editPV?.supplier_id || ''} disabled={readOnly}
                onChange={e => pickSupplier(e.target.value)} className={inputCls}>
                <option value="">— select supplier —</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}
              </select>
            ))}
            {h('Voucher Date', (
              <input type="date" value={editPV?.voucher_date || today()} disabled={readOnly}
                onChange={e => setEditPV(v => ({ ...v, voucher_date: e.target.value }))} className={inputCls} />
            ))}
            {h('Branch', (
              <select value={editPV?.branch_id || ''} disabled={readOnly}
                onChange={e => setEditPV(v => ({ ...v, branch_id: e.target.value }))} className={inputCls}>
                <option value="">— none —</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
              </select>
            ))}
            {h('Payment Mode', (
              <select value={editPV?.payment_mode_id || ''} disabled={readOnly}
                onChange={e => setEditPV(v => ({ ...v, payment_mode_id: e.target.value }))} className={inputCls}>
                <option value="">—</option>
                {paymentModes.map(pm => <option key={pm.id} value={pm.id}>{pm.name}</option>)}
              </select>
            ))}
            {h('Bank / Cash Account', (
              <select value={editPV?.bank_account_id || ''} disabled={readOnly}
                onChange={e => setEditPV(v => ({ ...v, bank_account_id: e.target.value }))} className={inputCls}>
                <option value="">— use default cash account —</option>
                {cashAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select>
            ))}
            {h('Reference / Check #', (
              <input value={editPV?.reference_number || ''} disabled={readOnly}
                onChange={e => setEditPV(v => ({ ...v, reference_number: e.target.value }))} className={inputCls} />
            ))}
            {h('Remarks', (
              <input value={editPV?.remarks || ''} disabled={readOnly}
                onChange={e => setEditPV(v => ({ ...v, remarks: e.target.value }))} className={inputCls} />
            ))}
          </div>
        </div>

        {/* Bills being paid */}
        <div className="bg-white border border-gray-200 rounded-lg mb-4 overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Bills Being Paid</span>
          </div>
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Vendor Bill','Outstanding Balance','Payment Amount','EWT Withheld','EWT Base','EWT ATC','Income Nature','Variance','Net Cash',''].map(h => (
                  <th key={h} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Outstanding Balance','Payment Amount','EWT Withheld','EWT Base','Net Cash'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map(l => (
                <tr key={l._key}>
                  <td className="px-3 py-2">
                    <select value={l.vendor_bill_id} disabled={readOnly || !editPV?.supplier_id}
                      onChange={e => pickBill(l._key, e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-48 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">— select bill —</option>
                      {openBills.map(b => <option key={b.id} value={b.id}>{b.bill_number} {b.supplier_invoice_number ? `(${b.supplier_invoice_number})` : ''}</option>)}
                    </select>
                  </td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-600">
                    {l.bill_outstanding > 0 ? fmt(l.bill_outstanding) : '—'}
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" value={l.payment_amount} min={0} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'payment_amount', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-28 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" value={l.ewt_amount} min={0} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'ewt_amount', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-24 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" value={l.ewt_tax_base} min={0} disabled={readOnly || l.ewt_amount === 0}
                      onChange={e => updateLine(l._key, 'ewt_tax_base', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-24 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    <select value={l.atc_code_id} disabled={readOnly || l.ewt_amount === 0}
                      onChange={e => updateLine(l._key, 'atc_code_id', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-32 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">—</option>
                      {atcCodes.map(a => <option key={a.id} value={a.id}>{a.code} — {a.description}</option>)}
                    </select>
                  </td>
                  <td className="px-3 py-2">
                    <input value={l.ewt_income_nature} disabled={readOnly || l.ewt_amount === 0}
                      onChange={e => updateLine(l._key, 'ewt_income_nature', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-44 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    <select value={l.ewt_variance_reason} disabled={readOnly || l.ewt_amount === 0}
                      onChange={e => updateLine(l._key, 'ewt_variance_reason', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-36 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">—</option>
                      {EWT_VARIANCE_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
                    </select>
                  </td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-semibold text-gray-900">
                    {fmt(l.payment_amount)}
                  </td>
                  <td className="px-3 py-2">
                    {!readOnly && lines.length > 1 && (
                      <button onClick={() => setLines(ls => ls.filter(x => x._key !== l._key))}
                        className="text-gray-400 hover:text-red-500 text-xs px-1">✕</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!readOnly && editPV?.supplier_id && (
            <div className="px-4 py-2 border-t border-gray-100">
              <button onClick={() => setLines(ls => [...ls, newLine()])}
                className="text-xs text-gray-500 hover:text-gray-900 font-medium">+ Add Bill</button>
            </div>
          )}
          {!readOnly && !editPV?.supplier_id && (
            <div className="px-4 py-2 text-xs text-gray-400">Select a supplier to load open bills.</div>
          )}
        </div>

        {/* Totals */}
        <div className="bg-white border border-gray-200 rounded-lg p-5 flex justify-end">
          <div className="grid grid-cols-2 gap-x-8 gap-y-1 text-sm min-w-[280px]">
            <span className="text-gray-500 text-xs">EWT Withheld</span>
            <span className="text-right font-mono text-xs text-blue-700">{fmt(totalEWT)}</span>
            <span className="text-gray-500 text-xs">AP Cleared (Cash + EWT)</span>
            <span className="text-right font-mono text-xs text-gray-700">{fmt(totalPayment + totalEWT)}</span>
            <span className="text-gray-900 font-semibold border-t border-gray-200 pt-1 mt-1">Cash Paid Out</span>
            <span className="text-right font-mono font-bold text-gray-900 border-t border-gray-200 pt-1 mt-1">{fmt(totalPayment)}</span>
          </div>
        </div>

        <GLImpactPanel
          companyId={companyId}
          sourceDocType="PV"
          sourceDocId={editPV?.id}
          previewRows={glImpactRows}
        />

        {editPV?.id && (
          <div className="mt-4 space-y-3">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Audit Evidence</div>
              <div className="grid grid-cols-1 sm:grid-cols-5 gap-3">
                {auditFacts.map(fact => (
                  <div key={fact.label}>
                    <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{fact.label}</div>
                    <div className="mt-1 text-xs text-gray-700">{fact.value}</div>
                  </div>
                ))}
              </div>
            </div>
            <AuditTrailSection tableName="payment_vouchers" recordId={editPV.id} />
          </div>
        )}

        {mode === 'view' && (
          <div className="mt-4 bg-blue-50 border border-blue-200 rounded-lg px-4 py-3 text-xs text-blue-700">
            This voucher is {editPV?.status}. To make changes, create a new payment voucher.
          </div>
        )}
      </div>
    </div>
  )
}
