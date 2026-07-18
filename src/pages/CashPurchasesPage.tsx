import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditEvidenceBlock, StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { normalizePhTin } from '@/lib/philippines'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'
import { useBranchLabel } from '@/hooks/useBranchLabel'

type CPStatus = 'draft' | 'posted' | 'cancelled'

type CP = {
  id: string; company_id: string; branch_id: string; cp_number: string; transaction_date: string
  warehouse_id?: string | null; department_id?: string | null; cost_center_id?: string | null
  supplier_id: string | null; supplier_name_snapshot: string | null; supplier_tin_snapshot: string | null
  payment_account_id: string | null
  payment_method: string; reference_number: string | null; remarks: string | null
  total_taxable_amount: number; total_input_vat_amount: number; total_ewt_amount: number; total_amount: number
  status: CPStatus; created_at: string; updated_at?: string | null; posted_at?: string | null
}

type CPLine = {
  _key: string; id?: string
  item_id: string; description: string; quantity: number; uom_id: string
  unit_price: number; net_amount: number; vat_code_id: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
  input_vat_amount: number; total_amount: number; expense_account_id: string
  ewt_atc_code_id: string; ewt_tax_base: number; ewt_amount: number
  ewt_income_nature: string; ewt_variance_reason: string
}

type SupplierRef = { id: string; registered_name: string; tin: string; is_subject_to_ewt: boolean; default_atc_code_id: string | null }
type ItemRef = { id: string; item_code: string; description: string; item_type: 'inventory_item' | 'service' | 'non_inventory'; uom_id: string; uom_label: string; standard_cost: number; default_purchase_vat_id: string | null; purchase_account_id: string | null; inventory_account_id: string | null }
type VATRef = { id: string; vat_code: string; description: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number }
type COARef = { id: string; account_code: string; account_name: string }
type ATCCode = { id: string; code: string; description: string; rate: number }
type DimensionRef = { id: string; branch_id: string | null; department_id?: string | null; code: string; name: string }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const round2 = (n: number) => Math.round(n * 100) / 100
const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'

const newLine = (): CPLine => ({
  _key: crypto.randomUUID(), item_id: '', description: '', quantity: 1, uom_id: '',
  unit_price: 0, net_amount: 0, vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  input_vat_amount: 0, total_amount: 0, expense_account_id: '',
  ewt_atc_code_id: '', ewt_tax_base: 0, ewt_amount: 0,
  ewt_income_nature: '', ewt_variance_reason: '',
})

const computeLine = (l: CPLine, atcCodes: ATCCode[] = []): CPLine => {
  const net = Math.max(round2(l.quantity * l.unit_price), 0)
  const vat = l.vat_classification === 'regular' ? round2(net * l.vat_rate / 100) : 0
  const atc = atcCodes.find(a => a.id === l.ewt_atc_code_id)
  const ewtBase = l.ewt_atc_code_id ? round2(Math.max(l.ewt_tax_base || net, 0)) : 0
  const ewtAmount = atc && ewtBase > 0 ? round2(ewtBase * atc.rate / 100) : (l.ewt_atc_code_id ? l.ewt_amount || 0 : 0)
  const cashTotal = Math.max(round2(net + vat - ewtAmount), 0)
  return {
    ...l,
    net_amount: net,
    input_vat_amount: vat,
    ewt_tax_base: ewtBase,
    ewt_amount: ewtAmount,
    ewt_income_nature: l.ewt_atc_code_id ? (l.ewt_income_nature || atc?.description || '') : '',
    ewt_variance_reason: l.ewt_atc_code_id ? l.ewt_variance_reason : '',
    total_amount: cashTotal,
  }
}

export default function CashPurchasesPage() {
  const { companyId, branchId } = useAppCtx()
  const [records, setRecords] = useState<CP[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editCP, setEditCP] = useState<Partial<CP> | null>(null)
  const [lines, setLines] = useState<CPLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])
  const [cashAccounts, setCashAccounts] = useState<COARef[]>([])
  const [expenseAccounts, setExpenseAccounts] = useState<COARef[]>([])
  const [warehouses, setWarehouses] = useState<DimensionRef[]>([])
  const [departments, setDepartments] = useState<DimensionRef[]>([])
  const [costCenters, setCostCenters] = useState<DimensionRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const readOnly = mode === 'view'
  const branchLabel = useBranchLabel(editCP?.branch_id || branchId)

  const loadRecords = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('cash_purchases').select('*').eq('company_id', companyId).order('transaction_date', { ascending: false }).order('cp_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`cp_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setRecords(data as CP[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadRecords() }, [loadRecords, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('suppliers').select('id,registered_name,tin,is_subject_to_ewt,default_atc_code_id').eq('company_id', companyId).eq('is_active', true).order('registered_name').then(({ data }) => setSuppliers(data as SupplierRef[] || []))
    supabase.from('items').select('id,item_code,description,item_type,uom_id,uom:units_of_measure(uom_code),standard_cost,default_purchase_vat_id,purchase_account_id:purchase_expense_account_id,inventory_account_id').eq('company_id', companyId).eq('is_active', true).order('description').then(({ data, error }) => { setItems((data || []).map((i: any) => ({ ...i, uom_label: i.uom?.uom_code || '' }))); if (error) setError(`Unable to load item picker: ${error.message}`) })
    Promise.all([
      supabase.from('companies').select('tax_registration').eq('id', companyId).single(),
      supabase.from('vat_codes').select('id,vat_code,description,vat_classification,tax_codes(rate)').eq('transaction_type', 'input_vat').eq('is_active', true),
    ]).then(([companyRes, vatRes]) => {
      const taxRegistration = companyRes.data?.tax_registration || 'vat'
      setVatCodes((vatRes.data || [])
        .map((v: any) => ({ id: v.id, vat_code: v.vat_code, description: v.description, vat_classification: v.vat_classification, rate: v.tax_codes?.rate || 0 }))
        .filter(v => taxRegistration === 'vat' || v.rate === 0))
    })
    supabase.from('atc_codes').select('id,code,description,rate').eq('is_active', true).eq('tax_category', 'ewt').order('code').then(({ data }) => setAtcCodes(data as ATCCode[] || []))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).in('account_type', ['asset']).eq('is_active', true).ilike('account_name', '%cash%').order('account_code').then(({ data }) => setCashAccounts(data as COARef[] || []))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).in('account_type', ['asset','expense','cost_of_goods']).eq('is_active', true).eq('is_postable', true).order('account_code').then(({ data }) => setExpenseAccounts(data as COARef[] || []))
    Promise.all([
      supabase.from('warehouses').select('id,branch_id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('departments').select('id,branch_id,department_code,department_name').eq('company_id', companyId).eq('is_active', true).order('department_code'),
      supabase.from('cost_centers').select('id,branch_id,department_id,cost_center_code,cost_center_name').eq('company_id', companyId).eq('is_active', true).order('cost_center_code'),
    ]).then(([warehouseRes, departmentRes, costCenterRes]) => {
      setWarehouses((warehouseRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, code: row.warehouse_code, name: row.warehouse_name })))
      setDepartments((departmentRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, code: row.department_code, name: row.department_name })))
      setCostCenters((costCenterRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, department_id: row.department_id, code: row.cost_center_code, name: row.cost_center_name })))
    })
  }, [companyId])

  const openNew = () => {
    setEditCP({ transaction_date: today(), payment_method: 'cash', branch_id: branchId || '', warehouse_id: warehouses[0]?.id || '', department_id: departments[0]?.id || '', cost_center_id: costCenters[0]?.id || '' })
    setLines([newLine()])
    setError('')
    setMode('edit')
  }

  const openEdit = (cp: CP) => {
    setEditCP({ ...cp })
    supabase.from('cash_purchase_lines').select('*').eq('cp_id', cp.id).order('line_number').then(({ data }) => setLines(data?.map((l: any) => {
      const vatRef = vatCodes.find(v => v.id === l.vat_code_id)
      return computeLine({
        ...l,
        _key: l.id,
        vat_classification: vatRef?.vat_classification || 'regular',
        vat_rate: vatRef?.rate ?? 12,
        ewt_atc_code_id: l.ewt_atc_code_id || '',
        ewt_tax_base: Number(l.ewt_tax_base || 0),
        ewt_amount: Number(l.ewt_amount || 0),
        ewt_income_nature: l.ewt_income_nature || '',
        ewt_variance_reason: l.ewt_variance_reason || '',
      } as CPLine, atcCodes)
    }) as CPLine[] || [newLine()]))
    setError('')
    setMode('edit')
  }

  const openView = (cp: CP) => {
    setEditCP({ ...cp })
    supabase.from('cash_purchase_lines').select('*').eq('cp_id', cp.id).order('line_number').then(({ data }) => setLines(data?.map((l: any) => {
      const vatRef = vatCodes.find(v => v.id === l.vat_code_id)
      return computeLine({
        ...l,
        _key: l.id,
        vat_classification: vatRef?.vat_classification || 'regular',
        vat_rate: vatRef?.rate ?? 12,
        ewt_atc_code_id: l.ewt_atc_code_id || '',
        ewt_tax_base: Number(l.ewt_tax_base || 0),
        ewt_amount: Number(l.ewt_amount || 0),
        ewt_income_nature: l.ewt_income_nature || '',
        ewt_variance_reason: l.ewt_variance_reason || '',
      } as CPLine, atcCodes)
    }) as CPLine[] || []))
    setMode('view')
  }

  const selectSupplier = (id: string) => {
    const s = suppliers.find(x => x.id === id)
    setEditCP(p => ({
      ...p,
      supplier_id: id || null,
      supplier_name_snapshot: s?.registered_name || '',
      supplier_tin_snapshot: s?.tin ? normalizePhTin(s.tin) : '',
    }))
    const defaultAtc = s?.is_subject_to_ewt ? s.default_atc_code_id || '' : ''
    setLines(prev => prev.map(l => computeLine({
      ...l,
      ewt_atc_code_id: defaultAtc || l.ewt_atc_code_id,
      ewt_tax_base: defaultAtc ? (l.ewt_tax_base || l.net_amount) : l.ewt_tax_base,
    }, atcCodes)))
  }

  const selectItem = (idx: number, id: string) => {
    const item = items.find(x => x.id === id)
    if (!item) return
    const vatRef = vatCodes.find(v => v.id === item.default_purchase_vat_id)
    updateLine(idx, {
      item_id: item.id, description: item.description, uom_id: item.uom_id,
      unit_price: item.standard_cost,
      vat_code_id: vatRef?.id || '',
      vat_classification: vatRef?.vat_classification || 'regular',
      vat_rate: vatRef?.rate ?? 0,
      expense_account_id: (item.item_type === 'inventory_item' ? item.inventory_account_id : item.purchase_account_id) || '',
      ewt_atc_code_id: lines[idx]?.ewt_atc_code_id || (suppliers.find(s => s.id === editCP?.supplier_id && s.is_subject_to_ewt)?.default_atc_code_id || ''),
    })
  }

  const selectVAT = (idx: number, id: string) => {
    const v = vatCodes.find(x => x.id === id)
    if (!v) return
    updateLine(idx, { vat_code_id: v.id, vat_classification: v.vat_classification, vat_rate: v.rate })
  }

  const selectEWT = (idx: number, id: string) => {
    const atc = atcCodes.find(x => x.id === id)
    updateLine(idx, {
      ewt_atc_code_id: atc?.id || '',
      ewt_tax_base: atc ? lines[idx]?.net_amount || 0 : 0,
      ewt_income_nature: atc?.description || '',
      ewt_variance_reason: '',
    })
  }

  const updateLine = (idx: number, patch: Partial<CPLine>) => {
    setLines(prev => prev.map((l, i) => i !== idx ? l : computeLine({ ...l, ...patch }, atcCodes)))
  }

  const totals = lines.reduce((acc, l) => ({
    taxable: acc.taxable + (l.vat_classification === 'regular' ? l.net_amount : 0),
    vat: acc.vat + l.input_vat_amount,
    gross: acc.gross + l.net_amount + l.input_vat_amount,
    ewtBase: acc.ewtBase + (l.ewt_atc_code_id ? l.ewt_tax_base : 0),
    ewt: acc.ewt + l.ewt_amount,
    cash: acc.cash + l.total_amount,
  }), { taxable: 0, vat: 0, gross: 0, ewtBase: 0, ewt: 0, cash: 0 })
  const requiredConfig = useMemo<ConfigField[]>(() => {
    const fields: ConfigField[] = []
    if (!editCP?.payment_account_id) fields.push('default_cash_account_id')
    if (totals.vat > 0.005) fields.push('input_vat_account_id')
    if (totals.ewt > 0.005) fields.push('ewt_payable_account_id')
    return fields
  }, [editCP?.payment_account_id, totals.ewt, totals.vat])
  const readiness = useTransactionReadiness({
    companyId,
    branchId: editCP?.branch_id || branchId,
    documentCode: 'CP',
    postingDate: editCP?.transaction_date || today(),
    requiredConfig,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0
  const auditFacts = editCP?.id ? [
    { label: 'Created', value: formatDateTime(editCP.created_at) },
    { label: 'Last edited', value: formatDateTime(editCP.updated_at) },
    { label: 'Posted', value: formatDateTime(editCP.posted_at) },
    { label: 'Status', value: editCP.status || 'draft' },
    { label: 'Lock status', value: editCP.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ] : []
  const glPreviewRows = useMemo<GLImpactRow[]>(() => [
    ...lines
      .filter(line => line.net_amount > 0.005)
      .map(line => ({
        accountId: line.expense_account_id || null,
        description: line.description || 'Cash purchase',
        debit: line.net_amount,
        credit: 0,
      })),
    ...(totals.vat > 0.005 ? [{
      configKey: 'input_vat_account_id' as const,
      description: 'Input VAT',
      debit: totals.vat,
      credit: 0,
    }] : []),
    ...(totals.ewt > 0.005 ? [{
      configKey: 'ewt_payable_account_id' as const,
      description: 'EWT payable',
      debit: 0,
      credit: totals.ewt,
    }] : []),
    {
      accountId: editCP?.payment_account_id || null,
      configKey: editCP?.payment_account_id ? undefined : 'default_cash_account_id',
      description: 'Cash or bank payment',
      debit: 0,
      credit: totals.cash,
    },
  ], [editCP?.payment_account_id, lines, totals.cash, totals.ewt, totals.vat])
  const ewtTraceFiltersForLine = (line: CPLine) => {
    const atc = atcCodes.find(a => a.id === line.ewt_atc_code_id)
    return {
      tax_kind: 'ewt_payable',
      source_doc_type: 'CP',
      source_doc_id: editCP?.id,
      atc_code_id: line.ewt_atc_code_id || undefined,
      income_nature: line.ewt_income_nature || undefined,
      tax_rate: atc ? String(atc.rate) : undefined,
    }
  }

  const save = async () => {
    if (setupBlocked) {
      setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0])
      return
    }
    if (!companyId) return
    if (!editCP?.warehouse_id && lines.some(line => line.item_id && items.find(item => item.id === line.item_id)?.item_type === 'inventory_item' && line.quantity > 0)) {
      setError('Warehouse is required for inventory-item cash purchases.')
      return
    }
    if (totals.ewt > 0.005 && !editCP?.supplier_id) {
      setError('Please select a supplier when EWT is recorded.')
      return
    }
    for (const line of lines.filter(l => l.description.trim())) {
      if (line.ewt_amount > 0.005 && !line.ewt_atc_code_id) {
        setError('ATC code is required when EWT is withheld.')
        return
      }
      if (line.ewt_amount > 0.005 && line.ewt_tax_base <= 0) {
        setError(`EWT taxable base is required for ${line.description || 'selected line'}.`)
        return
      }
    }
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_cash_purchase', {
        p_cp_id: (editCP?.id || null)!,
        p_header: {
          company_id: companyId, branch_id: editCP?.branch_id || branchId || null,
          warehouse_id: editCP?.warehouse_id || null,
          department_id: editCP?.department_id || null,
          cost_center_id: editCP?.cost_center_id || null,
          transaction_date: editCP?.transaction_date, payment_method: editCP?.payment_method || 'cash',
          supplier_id: editCP?.supplier_id || null,
          supplier_name_snapshot: editCP?.supplier_name_snapshot || '',
          supplier_tin_snapshot: editCP?.supplier_tin_snapshot || '',
          payment_account_id: (editCP as any)?.payment_account_id || null,
          reference_number: editCP?.reference_number || '',
          remarks: editCP?.remarks || '',
        },
        p_lines: lines.filter(l => l.description.trim()).map(l => ({
          item_id: l.item_id || null, description: l.description, quantity: l.quantity,
          uom_id: l.uom_id || null, unit_price: l.unit_price,
          vat_code_id: l.vat_code_id || null,
          expense_account_id: l.expense_account_id || null,
          ewt_atc_code_id: l.ewt_atc_code_id || null,
          ewt_tax_base: l.ewt_atc_code_id ? l.ewt_tax_base || l.net_amount : null,
          ewt_amount: l.ewt_amount || 0,
          ewt_income_nature: l.ewt_income_nature || null,
          ewt_variance_reason: l.ewt_variance_reason || null,
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadRecords()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const post = async (cp: CP) => {
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', {
      p_source_doc_type: 'CP',
      p_source_doc_id: cp.id,
    })
    if (previewError) { alert(`Cash Purchase is not ready to post: ${previewError.message}`); return }
    const { error: e } = await supabase.rpc('fn_post_cash_purchase', { p_cp_id: cp.id })
    if (e) { alert(e.message); return }
    loadRecords()
  }

  const STATUS_COLORS: Record<string, string> = { draft: 'draft', posted: 'posted', cancelled: 'error' }
  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'

  if (mode !== 'list') return (
    <LegacyTransactionWorkspace title="Cash Purchase" family="purchase" pattern="A" posting
      documentNo={editCP?.cp_number} status={editCP?.status} identity={editCP?.supplier_name_snapshot}
      financialFacts={[{ label: 'Cash Paid', value: fmt(totals.cash) }, { label: 'Gross Purchase', value: fmt(totals.gross) }, { label: 'Input VAT', value: fmt(totals.vat) }, { label: 'EWT', value: fmt(totals.ewt) }]}
      taxFacts={[{ label: 'Input VAT', value: fmt(totals.vat), hint: 'Calculated from line VAT treatment' }, { label: 'EWT', value: fmt(totals.ewt), hint: 'Calculated from line ATC and tax base' }, { label: 'EWT Tax Base', value: fmt(totals.ewtBase) }]}
      contextFacts={[{ label: 'Supplier', value: editCP?.supplier_name_snapshot || 'Not selected' }, { label: 'Transaction Date', value: editCP?.transaction_date || 'Not assigned' }, { label: 'Payment Method', value: editCP?.payment_method || 'Not selected' }]}
      sourceDocType="CP" sourceDocId={editCP?.id} auditTable="cash_purchases"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), hidden: readOnly },
        { key: 'save', label: saving ? 'Saving…' : 'Save', onClick: save, disabled: saving || setupBlocked, hidden: readOnly, variant: 'primary' },
        { key: 'post', label: 'Post Cash Purchase', onClick: () => post(editCP as CP), disabled: setupBlocked, hidden: !readOnly || editCP?.status !== 'draft', variant: 'primary' },
      ]}
      cards={[
        {
          title: 'Document Information',
          content: <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            <label className="pxl-field-label">Date *<input type="date" value={editCP?.transaction_date || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, transaction_date: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`} /></label>
            <div><div className="pxl-field-label">Branch</div><div className="pxl-readonly-field mt-1 truncate">{branchLabel}</div></div>
            <div><div className="pxl-field-label">Document Number</div><div className="pxl-readonly-field mt-1">{editCP?.cp_number || 'Generated on save'}</div></div>
            <div><div className="pxl-field-label">Status</div><div className="pxl-readonly-field mt-1 capitalize">{editCP?.status || 'draft'}</div></div>
          </div>,
        },
        {
          title: 'Supplier Information',
          content: <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            <label className="pxl-field-label col-span-2">Payee / Supplier<select value={editCP?.supplier_id || ''} disabled={readOnly} onChange={e => selectSupplier(e.target.value)} className={`${inp} pxl-input mt-1 w-full`}><option value="">— Optional —</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}</select></label>
            <div><div className="pxl-field-label">Supplier TIN</div><div className="pxl-readonly-field mt-1">{editCP?.supplier_tin_snapshot || 'Not selected'}</div></div>
            <div><div className="pxl-field-label">Supplier</div><div className="pxl-readonly-field mt-1 truncate">{editCP?.supplier_name_snapshot || 'Not selected'}</div></div>
          </div>,
        },
        {
          title: 'Purchase Context',
          content: <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            <label className="pxl-field-label">Payment Method<select value={editCP?.payment_method || 'cash'} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, payment_method: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`}><option value="cash">Cash</option><option value="check">Check</option><option value="transfer">Bank Transfer</option></select></label>
            <label className="pxl-field-label">Payment Account<select value={editCP?.payment_account_id || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, payment_account_id: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`}><option value="">— Select account —</option>{cashAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}</select></label>
            <label className="pxl-field-label">Reference No.<input type="text" value={editCP?.reference_number || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, reference_number: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`} placeholder="OR/Check/Transfer #" /></label>
            <label className="pxl-field-label">Remarks<input type="text" value={editCP?.remarks || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, remarks: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`} /></label>
            <label className="pxl-field-label">Warehouse<select value={editCP?.warehouse_id || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, warehouse_id: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`}><option value="">— Select warehouse —</option>{warehouses.filter(w => !editCP?.branch_id || !w.branch_id || w.branch_id === editCP.branch_id).map(w => <option key={w.id} value={w.id}>{w.code} — {w.name}</option>)}</select></label>
            <label className="pxl-field-label">Department<select value={editCP?.department_id || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, department_id: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`}><option value="">— Select department —</option>{departments.filter(d => !editCP?.branch_id || !d.branch_id || d.branch_id === editCP.branch_id).map(d => <option key={d.id} value={d.id}>{d.code} — {d.name}</option>)}</select></label>
            <label className="pxl-field-label">Cost Center<select value={editCP?.cost_center_id || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, cost_center_id: e.target.value }))} className={`${inp} pxl-input mt-1 w-full`}><option value="">— Select cost center —</option>{costCenters.filter(c => (!editCP?.branch_id || !c.branch_id || c.branch_id === editCP.branch_id) && (!editCP?.department_id || !c.department_id || c.department_id === editCP.department_id)).map(c => <option key={c.id} value={c.id}>{c.code} — {c.name}</option>)}</select></label>
          </div>,
        },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}<SetupReadinessBanner readiness={readiness} /></div>,
        gl: <GLImpactPanel companyId={companyId} sourceDocType="CP" sourceDocId={editCP?.id || null} previewRows={glPreviewRows} />,
        audit: editCP?.id ? <AuditEvidenceBlock tableName="cash_purchases" recordId={editCP.id} facts={auditFacts} /> : undefined,
      }}
      onBack={() => setMode('list')} backLabel="Cash Purchases">
    <div>
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Line Items</h3>
          {!readOnly && <button onClick={() => setLines(l => [...l, newLine()])} className="text-xs text-blue-600 hover:text-blue-800 font-medium">+ Add Line</button>}
        </div>
        <div className="overflow-x-auto">
        <table className="pxl-data-grid w-full min-w-[1180px] text-xs">
          <thead>
            <tr className="border-b border-gray-200 text-gray-500">
              <th className="text-left pb-2 font-medium w-36">Item</th>
              <th className="text-left pb-2 font-medium">Description</th>
              <th className="text-right pb-2 font-medium w-20">Qty</th>
              <th className="text-right pb-2 font-medium w-28">Unit Price</th>
              <th className="text-left pb-2 font-medium w-32">VAT</th>
              <th className="text-left pb-2 font-medium w-36">Expense Account</th>
              <th className="text-right pb-2 font-medium w-24">Net</th>
              <th className="text-right pb-2 font-medium w-24">VAT Amt</th>
              <th className="text-left pb-2 font-medium w-32">EWT ATC</th>
              <th className="text-right pb-2 font-medium w-24">EWT Base</th>
              <th className="text-right pb-2 font-medium w-24">EWT</th>
              <th className="text-right pb-2 font-medium w-24">Cash Paid</th>
              {!readOnly && <th className="w-8" />}
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={l._key} className="border-b border-gray-100">
                <td className="py-1.5 pr-1"><select value={l.item_id} disabled={readOnly} onChange={e => selectItem(i, e.target.value)} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-36 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{items.map(it => <option key={it.id} value={it.id}>{it.item_code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><input value={l.description} disabled={readOnly} onChange={e => updateLine(i, { description: e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.quantity} disabled={readOnly} onChange={e => updateLine(i, { quantity: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-20 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.unit_price} disabled={readOnly} onChange={e => updateLine(i, { unit_price: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-28 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><select value={l.vat_code_id} disabled={readOnly} onChange={e => selectVAT(i, e.target.value)} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-32 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><select value={l.expense_account_id} disabled={readOnly} onChange={e => updateLine(i, { expense_account_id: e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-36 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{expenseAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code}</option>)}</select></td>
                <td className="py-1.5 pr-1 text-right font-mono">{fmt(l.net_amount)}</td>
                <td className="py-1.5 pr-1 text-right font-mono text-blue-600">{fmt(l.input_vat_amount)}</td>
                <td className="py-1.5 pr-1"><select value={l.ewt_atc_code_id} disabled={readOnly} onChange={e => selectEWT(i, e.target.value)} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-32 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{atcCodes.map(a => <option key={a.id} value={a.id}>{a.code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.ewt_tax_base || 0} disabled={readOnly || !l.ewt_atc_code_id} onChange={e => updateLine(i, { ewt_tax_base: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-24 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1 text-right font-mono text-purple-700">
                  {readOnly && editCP?.id && l.ewt_amount > 0 ? (
                    <ReportTraceLink
                      companyId={companyId || ''}
                      reportFamily="tax"
                      filters={ewtTraceFiltersForLine(l)}
                      title="Open the EWT tax-ledger trace for this cash-purchase line"
                    >
                      {fmt(l.ewt_amount)}
                    </ReportTraceLink>
                  ) : fmt(l.ewt_amount)}
                </td>
                <td className="py-1.5 text-right font-mono font-medium">{fmt(l.total_amount)}</td>
                {!readOnly && <td className="py-1.5 pl-1"><button onClick={() => setLines(p => p.filter((_, j) => j !== i))} className="text-gray-300 hover:text-red-500 text-sm">×</button></td>}
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-gray-300 font-semibold text-xs">
              <td colSpan={6} className="pt-2 text-right text-gray-600 pr-2">Totals</td>
              <td className="pt-2 text-right font-mono">{fmt(totals.taxable)}</td>
              <td className="pt-2 text-right font-mono text-blue-600">{fmt(totals.vat)}</td>
              <td />
              <td className="pt-2 text-right font-mono">{fmt(totals.ewtBase)}</td>
              <td className="pt-2 text-right font-mono text-purple-700">
                {readOnly && editCP?.id && totals.ewt > 0 ? (
                  <ReportTraceLink
                    companyId={companyId || ''}
                    reportFamily="tax"
                    filters={{ tax_kind: 'ewt_payable', source_doc_type: 'CP', source_doc_id: editCP.id }}
                    title="Open all EWT tax-ledger rows for this cash purchase"
                  >
                    {fmt(totals.ewt)}
                  </ReportTraceLink>
                ) : fmt(totals.ewt)}
              </td>
              <td className="pt-2 text-right font-mono text-sm">{fmt(totals.cash)}</td>
            </tr>
          </tfoot>
        </table>
        </div>
      </div>

    </div>
    </LegacyTransactionWorkspace>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Cash Purchases</h2>
        <button onClick={openNew} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New Cash Purchase</button>
      </div>
      <div className="flex gap-2">
        <input placeholder="Search…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option><option value="draft">Draft</option><option value="posted">Posted</option><option value="cancelled">Cancelled</option>
        </select>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : records.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No cash purchases found.</div> : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['Date','CP Number','Payee','Method','EWT','Cash Paid','Status',''].map(h => <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {records.map(cp => (
                <tr key={cp.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={cp.transaction_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{cp.cp_number}</td>
                  <td className="px-3 py-2 text-gray-700">{cp.supplier_name_snapshot || '—'}</td>
                  <td className="px-3 py-2 capitalize text-gray-500">{cp.payment_method}</td>
                  <td className="px-3 py-2 text-right">
                    {cp.total_ewt_amount > 0 && cp.status !== 'draft' ? (
                      <ReportTraceLink
                        companyId={companyId || ''}
                        reportFamily="tax"
                        filters={{ tax_kind: 'ewt_payable', source_doc_type: 'CP', source_doc_id: cp.id }}
                        title="Open the EWT tax-ledger trace for this cash purchase"
                      >
                        <AmountCell amount={cp.total_ewt_amount || 0} />
                      </ReportTraceLink>
                    ) : <AmountCell amount={cp.total_ewt_amount || 0} />}
                  </td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={cp.total_amount} /></td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[cp.status]} label={cp.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => openView(cp)} className="text-blue-600 hover:text-blue-800">View</button>
                      {cp.status === 'draft' && <><button onClick={() => openEdit(cp)} className="text-gray-600 hover:text-gray-800">Edit</button><button onClick={() => post(cp)} className="text-green-600 hover:text-green-800">Post</button></>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </div>
    </div>
  )
}
