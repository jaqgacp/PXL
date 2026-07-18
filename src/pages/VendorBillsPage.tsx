import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge } from '@/components/ui/shared'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { normalizePhTin } from '@/lib/philippines'

// ── Types ─────────────────────────────────────────────────────
type VBStatus = 'draft' | 'approved' | 'posted' | 'cancelled'

type VB = {
  id: string; company_id: string; branch_id: string
  warehouse_id?: string | null; department_id?: string | null; cost_center_id?: string | null
  rr_id: string | null
  bill_number: string; supplier_invoice_number: string | null
  bill_date: string; due_date: string | null
  supplier_id: string; supplier_name_snapshot: string
  supplier_tin_snapshot: string | null; payment_terms_id: string | null
  currency_code: string; reference: string | null; memo: string | null
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_input_vat_amount: number
  total_amount: number; ewt_amount_expected: number | null
  status: VBStatus; void_reason_id: string | null; posted_at: string | null
  approved_at: string | null; updated_at: string | null; created_at: string
}

type VBLine = {
  _key: string; id?: string
  item_id: string; description: string
  quantity: number; uom_id: string; uom_label: string
  unit_price: number; discount_percent: number; discount_amount: number
  net_amount: number; vat_code_id: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
  input_vat_amount: number; total_amount: number
  expense_account_id: string
}

type SupplierRef = {
  id: string; registered_name: string; tin: string
  registered_address: string; default_tax_type: string
  default_terms_id: string | null; default_gl_account_id: string | null
  payment_terms?: { days_to_due: number } | null
}

type ItemRef = {
  id: string; item_code: string; description: string
  uom_id: string; uom_label: string; standard_selling_price: number
  item_type: 'inventory_item' | 'service' | 'non_inventory'; standard_cost: number
  default_purchase_vat_id: string | null; purchase_account_id: string | null; inventory_account_id: string | null
}

type VATRef = { id: string; vat_code: string; description: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number }
type TaxRegistration = 'vat' | 'non_vat' | 'exempt'
type COARef = { id: string; account_code: string; account_name: string; account_type: string }
type Branch = { id: string; branch_code: string; branch_name: string }
type VoidReason = { id: string; code: string; description: string }
type ReceivingReportRef = {
  id: string; rr_number: string; rr_date: string
  supplier_id: string; supplier_name_snapshot: string
  warehouse_id?: string | null; department_id?: string | null; cost_center_id?: string | null
}
type DimensionRef = { id: string; branch_id: string | null; department_id?: string | null; code: string; name: string }

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]

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

const newLine = (): VBLine => ({
  _key: crypto.randomUUID(), item_id: '', description: '',
  quantity: 1, uom_id: '', uom_label: '',
  unit_price: 0, discount_percent: 0, discount_amount: 0, net_amount: 0,
  vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  input_vat_amount: 0, total_amount: 0, expense_account_id: '',
})

const computeLine = (l: VBLine): VBLine => {
  const gross = l.unit_price * l.quantity
  const disc = gross * (l.discount_percent / 100)
  const net = Math.max(gross - disc, 0)
  const vat = l.vat_classification === 'regular' ? (net * l.vat_rate) / 100 : 0
  return { ...l, discount_amount: disc, net_amount: net, input_vat_amount: vat, total_amount: net + vat }
}

// ── Component ─────────────────────────────────────────────────
export default function VendorBillsPage() {
  const { companyId, branchId } = useAppCtx()

  const [bills, setBills] = useState<VB[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editVB, setEditVB] = useState<Partial<VB> | null>(null)
  const [lines, setLines] = useState<VBLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [voidTarget, setVoidTarget] = useState<VB | null>(null)
  const [voidReasonId, setVoidReasonId] = useState('')
  const [voidMemo, setVoidMemo] = useState('')

  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [taxRegistration, setTaxRegistration] = useState<TaxRegistration>('vat')
  const [expenseAccounts, setExpenseAccounts] = useState<COARef[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [voidReasons, setVoidReasons] = useState<VoidReason[]>([])
  const [receivingReports, setReceivingReports] = useState<ReceivingReportRef[]>([])
  const [warehouses, setWarehouses] = useState<DimensionRef[]>([])
  const [departments, setDepartments] = useState<DimensionRef[]>([])
  const [costCenters, setCostCenters] = useState<DimensionRef[]>([])

  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)

  const readOnly = mode === 'view'
  const requiredConfig = useMemo<ConfigField[]>(
    () => taxRegistration === 'vat'
      ? ['ap_account_id', 'input_vat_account_id']
      : ['ap_account_id'],
    [taxRegistration]
  )
  const readiness = useTransactionReadiness({
    companyId,
    branchId: mode === 'list' ? branchId : (editVB?.branch_id || branchId || ''),
    documentCode: 'VB',
    postingDate: editVB?.bill_date || today(),
    requiredConfig,
  })
  const allowsVatCode = useCallback((code: VATRef) => taxRegistration === 'vat' || code.rate === 0, [taxRegistration])
  const defaultVatCode = useCallback(() => vatCodes.find(allowsVatCode) || null, [allowsVatCode, vatCodes])
  const emptyLine = useCallback((): VBLine => {
    const vat = defaultVatCode()
    return {
      ...newLine(),
      vat_code_id: vat?.id || '',
      vat_classification: vat?.vat_classification || 'exempt',
      vat_rate: vat?.rate ?? 0,
    }
  }, [defaultVatCode])

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('vendor_bills').select('*')
      .eq('company_id', companyId).order('bill_date', { ascending: false }).order('bill_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    const { data } = await q
    setBills(data as VB[] || [])
    setLoading(false)
  }, [companyId, fStatus])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [companyRes, suppRes, vatRes, coaRes, brRes, vrRes, rrRes] = await Promise.all([
      supabase.from('companies').select('tax_registration').eq('id', companyId).single(),
      supabase.from('suppliers').select('id,registered_name,tin,registered_address,default_tax_type,default_terms_id,default_gl_account_id,payment_terms(days_to_due)').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('vat_codes').select('id,vat_code,description,vat_classification,tax_codes(rate)').eq('transaction_type', 'input_vat').eq('is_active', true),
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type').eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true),
      supabase.from('void_reason_codes').select('id,code,description'),
      supabase.from('receiving_reports' as any)
        .select('id,rr_number,rr_date,supplier_id,supplier_name_snapshot,warehouse_id,department_id,cost_center_id')
        .eq('company_id', companyId).eq('status', 'received')
        .order('rr_date', { ascending: false }),
    ])
    const companyTaxRegistration = ((companyRes.data?.tax_registration as TaxRegistration) || 'vat')
    setTaxRegistration(companyTaxRegistration)
    setSuppliers((suppRes.data || []).map((s: any) => ({ ...s, payment_terms: s.payment_terms })))
    setVatCodes((vatRes.data || [])
      .map((v: any) => ({ id: v.id, vat_code: v.vat_code, description: v.description, vat_classification: v.vat_classification, rate: v.tax_codes?.rate ?? 0 }))
      .filter((v: VATRef) => companyTaxRegistration === 'vat' || v.rate === 0))
    setExpenseAccounts(coaRes.data as COARef[] || [])
    setBranches(brRes.data as Branch[] || [])
    setVoidReasons(vrRes.data as VoidReason[] || [])
    setReceivingReports((rrRes.data as unknown as ReceivingReportRef[]) || [])
    const [warehouseRes, departmentRes, costCenterRes] = await Promise.all([
      supabase.from('warehouses').select('id,branch_id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('departments').select('id,branch_id,department_code,department_name').eq('company_id', companyId).eq('is_active', true).order('department_code'),
      supabase.from('cost_centers').select('id,branch_id,department_id,cost_center_code,cost_center_name').eq('company_id', companyId).eq('is_active', true).order('cost_center_code'),
    ])
    setWarehouses((warehouseRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, code: row.warehouse_code, name: row.warehouse_name })))
    setDepartments((departmentRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, code: row.department_code, name: row.department_name })))
    setCostCenters((costCenterRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, department_id: row.department_id, code: row.cost_center_code, name: row.cost_center_name })))
    // Items
    const { data: itemData, error: itemError } = await supabase.from('items').select('id,item_code,description,item_type,uom_id,units_of_measure(uom_code),standard_selling_price,standard_cost,default_purchase_vat_id,purchase_account_id:purchase_expense_account_id,inventory_account_id').eq('company_id', companyId).eq('is_active', true).order('item_code')
    setItems((itemData || []).map((i: any) => ({ ...i, uom_label: i.units_of_measure?.uom_code ?? '' })))
    if (itemError) setError(`Unable to load item picker: ${itemError.message}`)
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])
  useEffect(() => { if (companyId) load() }, [load, fStatus, companyId])

  const openNew = () => {
    if (readiness.blockers.length > 0) {
      setError('Complete company, branch, fiscal period, number series, and GL posting setup before creating a vendor bill.')
      return
    }
    setEditVB({ company_id: companyId!, branch_id: branchId || '', bill_date: today(), currency_code: 'PHP', status: 'draft', warehouse_id: warehouses[0]?.id || '', department_id: departments[0]?.id || '', cost_center_id: costCenters[0]?.id || '' })
    setLines([emptyLine()])
    setError('')
    setMode('edit')
  }

  const openEdit = (vb: VB) => {
    setEditVB(vb)
    supabase.from('vendor_bill_lines').select('*').eq('vendor_bill_id', vb.id).order('line_number').then(({ data }) => {
      if (data && data.length > 0) {
        const mapped: VBLine[] = data.map((l: any) => {
          const vc = vatCodes.find(v => v.id === l.vat_code_id)
          return {
            _key: l.id, id: l.id, item_id: l.item_id || '', description: l.description,
            quantity: Number(l.quantity), uom_id: l.uom_id || '', uom_label: '',
            unit_price: Number(l.unit_price), discount_percent: Number(l.discount_percent),
            discount_amount: Number(l.discount_amount), net_amount: Number(l.net_amount),
            vat_code_id: l.vat_code_id || '',
            vat_classification: vc?.vat_classification ?? 'regular',
            vat_rate: vc?.rate ?? 12,
            input_vat_amount: Number(l.input_vat_amount), total_amount: Number(l.total_amount),
            expense_account_id: l.expense_account_id || '',
          }
        })
        setLines(mapped)
      } else {
        setLines([emptyLine()])
      }
    })
    setError('')
    setMode(vb.status === 'draft' ? 'edit' : 'view')
  }

  const pickSupplier = (id: string) => {
    const s = suppliers.find(x => x.id === id)
    if (!s) return
    const daysToAdd = s.payment_terms?.days_to_due
    const due = daysToAdd ? new Date(Date.now() + daysToAdd * 86400000).toISOString().split('T')[0] : undefined
    setEditVB(v => ({ ...v, supplier_id: id, supplier_name_snapshot: s.registered_name,
      supplier_tin_snapshot: normalizePhTin(s.tin), payment_terms_id: s.default_terms_id || '', due_date: due || v?.due_date,
      rr_id: receivingReports.some(rr => rr.id === v?.rr_id && rr.supplier_id === id) ? v?.rr_id : null }))
  }

  const pickReceivingReport = (id: string) => {
    if (!id) {
      setEditVB(v => ({ ...v, rr_id: null }))
      return
    }
    const rr = receivingReports.find(row => row.id === id)
    const supplier = rr ? suppliers.find(row => row.id === rr.supplier_id) : null
    if (!rr || !supplier) return
    setEditVB(v => ({
      ...v,
      rr_id: rr.id,
      warehouse_id: rr.warehouse_id || v?.warehouse_id || '',
      department_id: rr.department_id || v?.department_id || '',
      cost_center_id: rr.cost_center_id || v?.cost_center_id || '',
      supplier_id: supplier.id,
      supplier_name_snapshot: supplier.registered_name,
      supplier_tin_snapshot: normalizePhTin(supplier.tin),
      payment_terms_id: supplier.default_terms_id || v?.payment_terms_id || '',
    }))
  }

  const pickItem = (lineKey: string, itemId: string) => {
    const item = items.find(i => i.id === itemId)
    if (!item) return
    const itemVat = vatCodes.find(v => v.id === item.default_purchase_vat_id)
    const vc = itemVat && allowsVatCode(itemVat) ? itemVat : defaultVatCode()
    setLines(ls => ls.map(l => l._key !== lineKey ? l : computeLine({
      ...l, item_id: item.id, description: item.description,
      uom_id: item.uom_id, uom_label: item.uom_label,
      unit_price: item.standard_cost || item.standard_selling_price,
      vat_code_id: vc?.id || '', vat_classification: vc?.vat_classification || 'exempt',
      vat_rate: vc?.rate ?? 0,
      expense_account_id: (item.item_type === 'inventory_item' ? item.inventory_account_id : item.purchase_account_id) || l.expense_account_id,
    })))
  }

  const pickVat = (lineKey: string, vatId: string) => {
    const vc = vatCodes.find(v => v.id === vatId)
    setLines(ls => ls.map(l => l._key !== lineKey ? l : computeLine({
      ...l, vat_code_id: vatId, vat_classification: vc?.vat_classification || 'exempt', vat_rate: vc?.rate ?? 0,
    })))
  }

  const updateLine = (key: string, field: keyof VBLine, raw: string) => {
    setLines(ls => ls.map(l => {
      if (l._key !== key) return l
      const updated = { ...l, [field]: ['quantity','unit_price','discount_percent'].includes(field) ? parseFloat(raw) || 0 : raw }
      return computeLine(updated)
    }))
  }

  const totals = lines.reduce((acc, l) => ({
    taxable: acc.taxable + (l.vat_classification === 'regular' ? l.net_amount : 0),
    zero: acc.zero + (l.vat_classification === 'zero_rated' ? l.net_amount : 0),
    exempt: acc.exempt + (l.vat_classification === 'exempt' ? l.net_amount : 0),
    vat: acc.vat + l.input_vat_amount,
    total: acc.total + l.total_amount,
  }), { taxable: 0, zero: 0, exempt: 0, vat: 0, total: 0 })
  const expenseImpactRows: GLImpactRow[] = Array.from(
    lines.reduce((map, line) => {
      const key = line.expense_account_id || 'missing_expense_account'
      const existing = map.get(key) || {
        accountId: line.expense_account_id || null,
        accountLabel: line.expense_account_id ? undefined : 'Missing expense account',
        description: 'Expense / inventory',
        debit: 0,
        credit: 0,
      }
      existing.debit += line.net_amount
      map.set(key, existing)
      return map
    }, new Map<string, GLImpactRow>()).values()
  )
  const glImpactRows: GLImpactRow[] = [
    ...expenseImpactRows,
    ...(totals.vat > 0
      ? [{ configKey: 'input_vat_account_id' as const, description: 'Input VAT', debit: totals.vat, credit: 0 }]
      : []),
    { configKey: 'ap_account_id', description: 'Accounts payable', debit: 0, credit: totals.total },
  ]

  const getAccountingReadinessErrors = () => {
    const activeLines = lines.filter(l => l.description.trim())
    const errors: string[] = []
    if (activeLines.length === 0) errors.push('At least one bill line is required.')
    if (activeLines.some(l => !l.expense_account_id || !expenseAccounts.some(a => a.id === l.expense_account_id))) {
      errors.push('Every bill line needs an active expense account before approval or posting.')
    }
    if (activeLines.some(l => !l.vat_code_id || !vatCodes.some(v => v.id === l.vat_code_id))) {
      errors.push('Every bill line needs an active input VAT code before approval or posting.')
    }
    return errors
  }

  const save = async (nextStatus: string) => {
    if (!companyId || !editVB) return
    if (readiness.blockers.length > 0) {
      setError('Complete setup readiness blockers before saving or posting this vendor bill.')
      return
    }
    if (nextStatus === 'approved' || nextStatus === 'posted') {
      const accountingErrors = getAccountingReadinessErrors()
      if (accountingErrors.length > 0) {
        setError(accountingErrors[0])
        return
      }
    }
    setSaving(true); setError('')
    try {
      const header = {
        company_id: companyId, branch_id: editVB.branch_id || branchId || '',
        supplier_id: editVB.supplier_id || '',
        warehouse_id: editVB.warehouse_id || '',
        department_id: editVB.department_id || '',
        cost_center_id: editVB.cost_center_id || '',
        rr_id: editVB.rr_id || '',
        supplier_name_snapshot: editVB.supplier_name_snapshot || '',
        supplier_tin_snapshot: editVB.supplier_tin_snapshot || '',
        supplier_invoice_number: editVB.supplier_invoice_number || '',
        bill_date: editVB.bill_date || today(), due_date: editVB.due_date || '',
        payment_terms_id: editVB.payment_terms_id || '',
        currency_code: editVB.currency_code || 'PHP',
        reference: editVB.reference || '', memo: editVB.memo || '',
        ewt_amount_expected: editVB.ewt_amount_expected?.toString() || '',
      }
      const linesPayload = lines.map(l => ({
        item_id: l.item_id, description: l.description,
        quantity: l.quantity, uom_id: l.uom_id,
        unit_price: l.unit_price, discount_percent: l.discount_percent,
        discount_amount: l.discount_amount, net_amount: l.net_amount,
        vat_code_id: l.vat_code_id, input_vat_amount: l.input_vat_amount,
        total_amount: l.total_amount, expense_account_id: l.expense_account_id,
      }))

      const { data: billId, error: saveErr } = await supabase.rpc('fn_save_vendor_bill', {
        p_bill_id: (editVB.id || null)!, p_header: header, p_lines: linesPayload,
      })
      if (saveErr) throw saveErr

      if (nextStatus === 'approved') {
        const { error: appErr } = await supabase.rpc('fn_approve_vendor_bill', { p_bill_id: billId })
        if (appErr) throw appErr
      }
      if (nextStatus === 'posted') {
        const { error: postErr } = await supabase.rpc('fn_post_vendor_bill', { p_bill_id: billId })
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

  const doRevertToDraft = async () => {
    if (!editVB?.id) return
    setSaving(true); setError('')
    const { error: e } = await supabase.rpc('fn_revert_vendor_bill_to_draft', { p_bill_id: editVB.id })
    if (e) { setError(e.message); setSaving(false); return }
    openEdit({ ...editVB as VB, status: 'draft' })
    setSaving(false)
  }

  const doVoid = async () => {
    if (!voidTarget || !voidReasonId) return
    setSaving(true); setError('')
    const { error: e } = await supabase.rpc('fn_void_vendor_bill', {
      p_bill_id: voidTarget.id, p_void_reason_id: voidReasonId, p_memo: voidMemo || undefined,
    })
    if (e) { setError(e.message); setSaving(false); return }
    setVoidTarget(null); setVoidReasonId(''); setVoidMemo('')
    await load(); setMode('list')
    setSaving(false)
  }

  const filtered = bills.filter(b =>
    !fSearch || b.bill_number.includes(fSearch) ||
    b.supplier_name_snapshot.toLowerCase().includes(fSearch.toLowerCase()) ||
    (b.supplier_invoice_number || '').includes(fSearch) ||
    (b.reference || '').toLowerCase().includes(fSearch.toLowerCase())
  )

  // ── List View ────────────────────────────────────────────────
  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Vendor Bills</span>
        <input value={fSearch} onChange={e => setFSearch(e.target.value)} placeholder="Search bill # / supplier / ref…"
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-56 focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="approved">Approved</option>
          <option value="posted">Posted</option>
          <option value="cancelled">Void</option>
        </select>
        <button onClick={openNew} disabled={readiness.loading || readiness.blockers.length > 0}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed">
          + New Vendor Bill
        </button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>

      {companyId && readiness.blockers.length > 0 && (
        <div className="px-5 py-3 border-b border-gray-100">
          <SetupReadinessBanner readiness={readiness} />
        </div>
      )}

      <div ref={listRef}>
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => (
            <div key={i} className="px-5 py-3 flex gap-4 animate-pulse">
              <div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" />
            </div>
          ))}</div>
        ) : filtered.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No vendor bills</p>
            <p className="text-xs text-gray-400 mt-1">Create your first vendor bill to track payables.</p>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Bill #','External Ref','Supplier Ref','Date','Due','Supplier','Taxable','Input VAT','Total','Status'].map(h => (
                  <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Taxable','Input VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtered.map(vb => (
                <tr key={vb.id} onClick={() => openEdit(vb)}
                  className={`cursor-pointer hover:bg-gray-50/60 ${vb.status === 'cancelled' ? 'opacity-50' : ''}`}>
                  <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">{vb.bill_number}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{vb.reference || '—'}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{vb.supplier_invoice_number || '—'}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{vb.bill_date}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{vb.due_date || '—'}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-900 max-w-[160px] truncate">{vb.supplier_name_snapshot}</td>
                  <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(vb.total_taxable_amount)}</td>
                  <td className="px-3 py-2.5 text-right font-mono text-xs text-blue-600">{fmt(vb.total_input_vat_amount)}</td>
                  <td className="px-3 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(vb.total_amount)}</td>
                  <td className="px-3 py-2.5"><StatusBadge status={vb.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Void dialog */}
      {voidTarget && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl p-6 w-full max-w-sm">
            <h3 className="font-semibold text-gray-900 mb-1">Void Vendor Bill</h3>
            <p className="text-xs text-gray-500 mb-4">{voidTarget.bill_number}</p>
            <select value={voidReasonId} onChange={e => setVoidReasonId(e.target.value)}
              className="w-full border border-gray-300 rounded px-2.5 py-2 text-sm mb-3 focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="">Select void reason…</option>
              {voidReasons.map(r => <option key={r.id} value={r.id}>{r.code} — {r.description}</option>)}
            </select>
            <textarea value={voidMemo} onChange={e => setVoidMemo(e.target.value)} rows={2}
              placeholder="Additional memo (optional)" className="w-full border border-gray-300 rounded px-2.5 py-2 text-sm mb-4 resize-none focus:outline-none focus:ring-1 focus:ring-gray-900" />
            {error && <p className="text-red-600 text-xs mb-3">{error}</p>}
            <div className="flex gap-2 justify-end">
              <button onClick={() => { setVoidTarget(null); setError('') }}
                className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={doVoid} disabled={!voidReasonId || saving}
                className="px-3 py-1.5 bg-red-600 text-white rounded text-sm hover:bg-red-700 disabled:opacity-50">Void Bill</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )

  // ── Edit / View ──────────────────────────────────────────────
  const h = (label: string, children: React.ReactNode) => (
    <div className="flex flex-col gap-1">
      <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>
      {children}
    </div>
  )
  const inputCls = `border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50 disabled:text-gray-500 w-full`
  const auditFacts = [
    { label: 'Created', value: formatDateTime(editVB?.created_at) },
    { label: 'Last edited', value: formatDateTime(editVB?.updated_at) },
    { label: 'Approved', value: formatDateTime(editVB?.approved_at) },
    { label: 'Posted', value: formatDateTime(editVB?.posted_at) },
    { label: 'Lock status', value: editVB?.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ]

  const selectedSupplier = suppliers.find(supplier => supplier.id === editVB?.supplier_id)
  const selectedBranch = branches.find(branch => branch.id === editVB?.branch_id)
  const selectedReceivingReport = receivingReports.find(report => report.id === editVB?.rr_id)
  const validationErrors = getAccountingReadinessErrors()
  const workflowSteps = [
    { key: 'draft', label: 'Draft' },
    { key: 'approved', label: 'Approved' },
    { key: 'posted', label: 'Posted' },
    { key: 'cancelled', label: 'Voided' },
  ]

  return (
    <>
      <TransactionWorkspace
        title="Vendor Bill"
        documentNo={editVB?.bill_number}
        status={editVB?.status || 'draft'}
        statusLabel={editVB?.status === 'cancelled' ? 'Voided' : editVB?.status}
        family="purchase"
        identity={{
          name: editVB?.supplier_name_snapshot || selectedSupplier?.registered_name || 'Supplier not selected',
          secondary: editVB?.supplier_tin_snapshot || selectedSupplier?.tin || undefined,
        }}
        metrics={[
          { label: 'Bill Total', value: `₱${fmt(totals.total)}`, emphasis: true },
          { label: 'Input VAT', value: `₱${fmt(totals.vat)}` },
          { label: 'Expected EWT', value: `₱${fmt(Number(editVB?.ewt_amount_expected || 0))}` },
        ]}
        meta={[
          { label: 'Mode', value: readOnly ? 'Read only' : 'Editable', tone: readOnly ? 'warning' : 'info' },
          { label: 'Posting', value: editVB?.posted_at ? 'Posted' : 'Not posted', tone: editVB?.posted_at ? 'success' : 'neutral' },
        ]}
        actions={[
          ...(!readOnly ? [
            { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: () => save('draft'), disabled: saving || readiness.blockers.length > 0 },
            { key: 'approve', label: saving ? 'Saving…' : 'Save & Approve', onClick: () => save('approved'), disabled: saving || readiness.blockers.length > 0, variant: 'primary' as const },
          ] : []),
          ...(editVB?.status === 'approved' ? [
            { key: 'revert', label: 'Revert to Draft', onClick: doRevertToDraft, disabled: saving, group: 'more' as const },
            { key: 'post', label: saving ? 'Posting…' : 'Post', onClick: () => save('posted'), disabled: saving || readiness.blockers.length > 0, variant: 'primary' as const },
          ] : []),
          ...(editVB?.status === 'posted' ? [
            { key: 'void', label: 'Void', onClick: () => setVoidTarget(editVB as VB), disabled: saving, variant: 'danger' as const, group: 'more' as const },
          ] : []),
        ]}
        workflow={{ steps: workflowSteps, currentKey: editVB?.status || 'draft' }}
        cards={[
          {
            title: 'Document Information',
            content: (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                {h('Bill Date', (
                  <input type="date" value={editVB?.bill_date || today()} disabled={readOnly}
                    onChange={e => setEditVB(v => ({ ...v, bill_date: e.target.value }))} className={inputCls} />
                ))}
                {h('Due Date', (
                  <input type="date" value={editVB?.due_date || ''} disabled={readOnly}
                    onChange={e => setEditVB(v => ({ ...v, due_date: e.target.value }))} className={inputCls} />
                ))}
                {h('Branch', (
                  <select value={editVB?.branch_id || ''} disabled={readOnly}
                    onChange={e => setEditVB(v => ({ ...v, branch_id: e.target.value }))} className={inputCls}>
                    <option value="">— none —</option>
                    {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
                  </select>
                ))}
                {h('Currency', <input value={editVB?.currency_code || 'PHP'} disabled className={inputCls} />)}
              </div>
            ),
          },
          {
            title: 'Supplier Information',
            content: (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                {h('Supplier', (
                  <select value={editVB?.supplier_id || ''} disabled={readOnly}
                    onChange={e => pickSupplier(e.target.value)} className={inputCls}>
                    <option value="">— select supplier —</option>
                    {suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}
                  </select>
                ))}
                {h('Supplier Invoice #', (
                  <input value={editVB?.supplier_invoice_number || ''} disabled={readOnly}
                    onChange={e => setEditVB(v => ({ ...v, supplier_invoice_number: e.target.value }))} className={inputCls} />
                ))}
                <div>
                  <div className="pxl-field-label">Supplier TIN</div>
                  <div className="pxl-body-text mt-1 font-mono">{editVB?.supplier_tin_snapshot || selectedSupplier?.tin || '—'}</div>
                </div>
                <div>
                  <div className="pxl-field-label">Terms</div>
                  <div className="pxl-body-text mt-1">{selectedSupplier?.payment_terms?.days_to_due != null ? `${selectedSupplier.payment_terms.days_to_due} days` : 'Not configured'}</div>
                </div>
              </div>
            ),
          },
          {
            title: 'Purchase Context',
            content: (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                {h('Receiving Report', (
                  <select value={editVB?.rr_id || ''} disabled={readOnly}
                    onChange={e => pickReceivingReport(e.target.value)} className={inputCls}>
                    <option value="">— direct bill / no RR —</option>
                    {receivingReports
                      .filter(rr => !editVB?.supplier_id || rr.supplier_id === editVB.supplier_id)
                      .map(rr => <option key={rr.id} value={rr.id}>{rr.rr_number} — {rr.rr_date}</option>)}
                  </select>
                ))}
                {h('Reference', (
                  <input value={editVB?.reference || ''} disabled={readOnly}
                    onChange={e => setEditVB(v => ({ ...v, reference: e.target.value }))} className={inputCls} />
                ))}
                {h('Warehouse', (
                  <select value={editVB?.warehouse_id || ''} disabled={readOnly} onChange={e => setEditVB(v => ({ ...v, warehouse_id: e.target.value }))} className={inputCls}>
                    <option value="">— select warehouse —</option>{warehouses.filter(w => !editVB?.branch_id || !w.branch_id || w.branch_id === editVB.branch_id).map(w => <option key={w.id} value={w.id}>{w.code} — {w.name}</option>)}
                  </select>
                ))}
                {h('Department', (
                  <select value={editVB?.department_id || ''} disabled={readOnly} onChange={e => setEditVB(v => ({ ...v, department_id: e.target.value }))} className={inputCls}>
                    <option value="">— select department —</option>{departments.filter(d => !editVB?.branch_id || !d.branch_id || d.branch_id === editVB.branch_id).map(d => <option key={d.id} value={d.id}>{d.code} — {d.name}</option>)}
                  </select>
                ))}
                {h('Cost Center', (
                  <select value={editVB?.cost_center_id || ''} disabled={readOnly} onChange={e => setEditVB(v => ({ ...v, cost_center_id: e.target.value }))} className={inputCls}>
                    <option value="">— select cost center —</option>{costCenters.filter(c => (!editVB?.branch_id || !c.branch_id || c.branch_id === editVB.branch_id) && (!editVB?.department_id || !c.department_id || c.department_id === editVB.department_id)).map(c => <option key={c.id} value={c.id}>{c.code} — {c.name}</option>)}
                  </select>
                ))}
                <div>
                  <div className="pxl-field-label">Posting Basis</div>
                  <div className="pxl-body-text mt-1">Expense / inventory, input VAT, and accounts payable</div>
                </div>
                <div>
                  <div className="pxl-field-label">Source Status</div>
                  <div className="pxl-body-text mt-1">{selectedReceivingReport ? `Received · ${selectedReceivingReport.rr_date}` : 'Direct vendor bill'}</div>
                </div>
              </div>
            ),
          },
        ]}
        tabBadges={{ lines: lines.length }}
        tabContent={{
          lines: (
            <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
              <table className="pxl-data-grid w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Item','Description','Qty','Unit Price','Disc %','VAT Code','Expense Account','Net','Input VAT','Total',''].map(h => (
                  <th key={h} className={`px-2.5 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Net','Input VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map((l) => (
                <tr key={l._key}>
                  <td className="px-2 py-1.5">
                    <select value={l.item_id} disabled={readOnly} onChange={e => pickItem(l._key, e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-36 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">—</option>
                      {items.map(i => <option key={i.id} value={i.id}>{i.item_code}</option>)}
                    </select>
                  </td>
                  <td className="px-2 py-1.5 min-w-[180px]">
                    <input value={l.description} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'description', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-2 py-1.5">
                    <input type="number" value={l.quantity} min={0} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'quantity', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-16 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-2 py-1.5">
                    <input type="number" value={l.unit_price} min={0} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'unit_price', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-24 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-2 py-1.5">
                    <input type="number" value={l.discount_percent} min={0} max={100} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'discount_percent', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-16 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-2 py-1.5">
                    <select value={l.vat_code_id} disabled={readOnly} onChange={e => pickVat(l._key, e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-28 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">—</option>
                      {vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}
                    </select>
                  </td>
                  <td className="px-2 py-1.5">
                    <select value={l.expense_account_id} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'expense_account_id', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-44 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">— select account —</option>
                      {expenseAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                    </select>
                  </td>
                  <td className="px-2 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(l.net_amount)}</td>
                  <td className="px-2 py-1.5 text-right font-mono tabular-nums text-blue-700">{fmt(l.input_vat_amount)}</td>
                  <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(l.total_amount)}</td>
                  <td className="px-2 py-1.5">
                    {!readOnly && lines.length > 1 && (
                      <button onClick={() => setLines(ls => ls.filter(x => x._key !== l._key))}
                        className="text-gray-400 hover:text-red-500 text-xs px-1">✕</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
              </table>
              {!readOnly && (
                <div className="px-4 py-2 border-t border-gray-100">
                  <button onClick={() => setLines(ls => [...ls, emptyLine()])}
                    className="pxl-button pxl-button--text">+ Add Line</button>
                </div>
              )}
            </div>
          ),
          financial: (
            <div className="ml-auto grid max-w-lg grid-cols-2 gap-x-8 gap-y-2 text-sm">
              {[
                ['Taxable Purchases', totals.taxable],
                ['Zero-Rated Purchases', totals.zero],
                ['Exempt Purchases', totals.exempt],
                ['Input VAT', totals.vat],
                ['Expected EWT', Number(editVB?.ewt_amount_expected || 0)],
                ['Amount Payable', totals.total],
              ].map(([label, value], index) => (
                <React.Fragment key={label as string}>
                  <span className={index === 5 ? 'pxl-section-title border-t pt-2' : 'text-gray-600'}>{label as string}</span>
                  <span className={`text-right font-mono tabular-nums ${index === 5 ? 'border-t pt-2 font-bold text-gray-900' : 'text-gray-800'}`}>₱{fmt(value as number)}</span>
                </React.Fragment>
              ))}
            </div>
          ),
          gl: (
            <GLImpactPanel companyId={companyId} sourceDocType="VB" sourceDocId={editVB?.id} previewRows={glImpactRows} />
          ),
          tax: (
            <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
              <table className="pxl-data-grid w-full">
                <thead><tr>{['Tax Treatment', 'Tax Base', 'Rate / Source', 'Tax Amount'].map(label => <th key={label} className={label.includes('Amount') ? 'text-right' : 'text-left'}>{label}</th>)}</tr></thead>
                <tbody>
                  <tr><td>Regular Input VAT</td><td className="font-mono text-right">₱{fmt(totals.taxable)}</td><td>Line VAT code</td><td className="font-mono text-right">₱{fmt(totals.vat)}</td></tr>
                  <tr><td>Zero-Rated</td><td className="font-mono text-right">₱{fmt(totals.zero)}</td><td>0%</td><td className="font-mono text-right">₱0.00</td></tr>
                  <tr><td>Exempt</td><td className="font-mono text-right">₱{fmt(totals.exempt)}</td><td>Exempt</td><td className="font-mono text-right">₱0.00</td></tr>
                  <tr><td>EWT</td><td className="font-mono text-right">—</td><td>Supplier tax profile / ATC</td><td className="font-mono text-right">₱{fmt(Number(editVB?.ewt_amount_expected || 0))}</td></tr>
                </tbody>
              </table>
            </div>
          ),
          validation: (
            <div className="space-y-3">
              {readiness.blockers.length > 0 && <SetupReadinessBanner readiness={readiness} />}
              {error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700" role="alert">{error}</div>}
              {validationErrors.length > 0 ? validationErrors.map(message => (
                <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>
              )) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Bill lines and accounting references are ready for the current lifecycle action.</div>}
            </div>
          ),
          workflow: (
            <ol className="grid gap-2 sm:grid-cols-4">
              {workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === (editVB?.status || 'draft') ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}
            </ol>
          ),
          approval: (
            <div className="grid gap-3 sm:grid-cols-3">
              <div><div className="pxl-field-label">Approval Status</div><div className="pxl-body-text mt-1">{editVB?.approved_at ? 'Approved' : 'Not approved'}</div></div>
              <div><div className="pxl-field-label">Approved At</div><div className="pxl-body-text mt-1">{formatDateTime(editVB?.approved_at)}</div></div>
              <div><div className="pxl-field-label">Next Action</div><div className="pxl-body-text mt-1">{editVB?.status === 'draft' ? 'Save & Approve' : editVB?.status === 'approved' ? 'Post' : 'No approval action available'}</div></div>
            </div>
          ),
          audit: editVB?.id ? (
            <div className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-5">
                {auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}
              </div>
              <AuditTrailSection tableName="vendor_bills" recordId={editVB.id} />
            </div>
          ) : <TransactionEmptyState>Audit history begins after the vendor bill is saved.</TransactionEmptyState>,
          related: selectedReceivingReport ? (
            <table className="pxl-data-grid w-full"><thead><tr><th className="text-left">Relationship</th><th className="text-left">Document</th><th className="text-left">Date</th><th className="text-left">Status</th></tr></thead><tbody><tr><td>Source receipt</td><td className="font-mono font-semibold">{selectedReceivingReport.rr_number}</td><td>{selectedReceivingReport.rr_date}</td><td>Received</td></tr></tbody></table>
          ) : <TransactionEmptyState>This is a direct vendor bill with no receiving report selected.</TransactionEmptyState>,
          party: selectedSupplier ? (
            <dl className="grid gap-3 sm:grid-cols-3">
              <div><dt className="pxl-field-label">Supplier</dt><dd className="pxl-body-text mt-1">{selectedSupplier.registered_name}</dd></div>
              <div><dt className="pxl-field-label">TIN</dt><dd className="pxl-body-text mt-1 font-mono">{selectedSupplier.tin || '—'}</dd></div>
              <div><dt className="pxl-field-label">Registered Address</dt><dd className="pxl-body-text mt-1">{selectedSupplier.registered_address || '—'}</dd></div>
            </dl>
          ) : <TransactionEmptyState>Select a supplier to see the related-party summary.</TransactionEmptyState>,
          activity: (
            <div className="grid gap-3 sm:grid-cols-4">{auditFacts.slice(0, 4).map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div>
          ),
          notes: h('Vendor Bill Memo', (
            <textarea value={editVB?.memo || ''} disabled={readOnly} rows={5}
              onChange={e => setEditVB(v => ({ ...v, memo: e.target.value }))} className={inputCls} />
          )),
          system: (
            <SystemMetadataPanel facts={[
              { label: 'Internal ID', value: editVB?.id || 'Assigned when saved', hint: 'Transaction identity' },
              { label: 'Document Number', value: editVB?.bill_number || 'Generated from number series', hint: 'Vendor bill number' },
              { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
              { label: 'Branch', value: selectedBranch ? `${selectedBranch.branch_code} — ${selectedBranch.branch_name}` : editVB?.branch_id || '—', hint: 'Posting context' },
              { label: 'Created', value: formatDateTime(editVB?.created_at), hint: 'Audit metadata' },
              { label: 'Updated', value: formatDateTime(editVB?.updated_at), hint: 'Audit metadata' },
              { label: 'Posted', value: formatDateTime(editVB?.posted_at), hint: 'Lifecycle metadata' },
              { label: 'Lock Status', value: editVB?.status === 'draft' ? 'Editable draft' : 'Lifecycle locked', hint: 'Immutability control' },
            ]} />
          ),
        }}
        emptyTabMessages={{
          attachments: 'No attachments have been added to this vendor bill.',
        }}
        sidebarPanels={[
          { key: 'balance', title: 'Balance', content: <div className="flex items-baseline justify-between gap-3"><span className="pxl-field-label">Amount Payable</span><span className="font-mono text-sm font-bold">₱{fmt(totals.total)}</span></div> },
          { key: 'tax', title: 'Tax', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Input VAT</span><span className="font-mono text-xs">₱{fmt(totals.vat)}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Expected EWT</span><span className="font-mono text-xs">₱{fmt(Number(editVB?.ewt_amount_expected || 0))}</span></div></div> },
          { key: 'gl', title: 'GL Preview', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Debit</span><span className="font-mono text-xs">₱{fmt(glImpactRows.reduce((sum, row) => sum + row.debit, 0))}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Credit</span><span className="font-mono text-xs">₱{fmt(glImpactRows.reduce((sum, row) => sum + row.credit, 0))}</span></div></div> },
          { key: 'supplier', title: 'Supplier', content: <div><div className="text-xs font-semibold text-gray-800">{editVB?.supplier_name_snapshot || selectedSupplier?.registered_name || 'Not selected'}</div><div className="pxl-caption mt-1 font-mono">{editVB?.supplier_tin_snapshot || selectedSupplier?.tin || 'No TIN'}</div></div> },
          { key: 'audit', title: 'Audit', content: <div className="pxl-caption">{editVB?.status === 'draft' ? 'Draft remains editable.' : 'Document is frozen by lifecycle controls.'}</div> },
        ]}
        footer={<span>Created {formatDateTime(editVB?.created_at)} · Updated {formatDateTime(editVB?.updated_at)}</span>}
        onBack={() => setMode('list')}
        backLabel="Vendor Bills"
      />

      {voidTarget && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl p-6 w-full max-w-sm">
            <h3 className="font-semibold text-gray-900 mb-1">Void Vendor Bill</h3>
            <p className="text-xs text-gray-500 mb-4">{voidTarget.bill_number}</p>
            <select value={voidReasonId} onChange={e => setVoidReasonId(e.target.value)} className="w-full border border-gray-300 rounded px-2.5 py-2 text-sm mb-3">
              <option value="">Select void reason…</option>
              {voidReasons.map(r => <option key={r.id} value={r.id}>{r.code} — {r.description}</option>)}
            </select>
            <textarea value={voidMemo} onChange={e => setVoidMemo(e.target.value)} rows={2} placeholder="Additional memo (optional)" className="w-full border border-gray-300 rounded px-2.5 py-2 text-sm mb-4 resize-none" />
            <div className="flex gap-2 justify-end">
              <button onClick={() => { setVoidTarget(null); setError('') }} className="pxl-button pxl-button--neutral">Cancel</button>
              <button onClick={doVoid} disabled={!voidReasonId || saving} className="pxl-button pxl-button--danger">Void Bill</button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
