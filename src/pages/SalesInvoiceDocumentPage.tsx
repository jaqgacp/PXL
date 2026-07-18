import { useState, useEffect, useCallback, type ReactNode } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { WorkflowStrip, type ToolbarAction } from '@/components/document/DocumentLayout'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { PrimaryInformationPanel, type InfoGroup } from '@/components/document/PrimaryInformationPanel'
import { PostingValidationPanel, readinessToChecks, type ValidationCheck } from '@/components/document/PostingValidationPanel'
import { LineGrid, type LineColumn, type LineColumnProfile } from '@/components/document/LineGrid'
import { LineDetailPanel, type DetailSection } from '@/components/document/LineDetailPanel'
import { TaxImpactPanel } from '@/components/document/TaxImpactPanel'
import { RelatedDocumentsTab, type RelatedDocRow } from '@/components/document/RelatedDocumentsTab'
import { ErpSectionHeader, CompactEmptyState, ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH, ERP_TD, ERP_TD_NUM } from '@/components/document/ErpSection'
import { GLImpactPanel, type ServerGLImpact, type WithholdingInfo } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { AuditTrailSection, StatusBadge, AmountCell, DateCell, EmptyState } from '@/components/ui/shared'
import { composePhTin, getPhTinBranch, normalizePhTin } from '@/lib/philippines'

// Stable identity so the readiness effect doesn't re-run each render.
const SI_REQUIRED_CONFIG: ConfigField[] = ['ar_account_id', 'vat_payable_account_id']

// ─────────────────────────────────────────────────────────────
// Sales Invoice routed document view. Its business content composes the same
// TransactionWorkspace architecture used by every other document family.
// ─────────────────────────────────────────────────────────────

type SIStatus = 'draft' | 'approved' | 'posted' | 'cancelled'

type SIRow = {
  id: string; company_id: string; branch_id: string
  si_number: string; date: string; customer_id: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  customer_address_snapshot: string; payment_terms_id: string | null
  due_date: string | null; currency_code: string
  vat_price_basis: 'exclusive' | 'inclusive'
  department_id: string | null; cost_center_id: string | null
  warehouse_id: string | null; salesperson_id: string | null
  account_owner_id: string | null
  reference: string | null; memo: string | null
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_vat_amount: number
  total_amount: number; status: SIStatus
  cwt_amount_expected: number | null
  fiscal_period_id: string | null; journal_entry_id: string | null
  created_by: string | null; updated_by: string | null
  approved_by: string | null; posted_by: string | null
  approved_at: string | null; posted_at: string | null
  created_at: string; updated_at: string
}

type LineRow = {
  id: string; line_number: number; item_id: string | null; description: string
  quantity: number; uom_id: string | null; unit_price: number
  discount_percent: number; discount_amount: number
  net_amount: number; vat_code_id: string | null; vat_amount: number; total_amount: number
  revenue_account_id: string | null
  warehouse_id: string | null; department_id: string | null; cost_center_id: string | null
  salesperson_id: string | null; inventory_account_id: string | null; cogs_account_id: string | null
  unit_cost: number | null; inventory_cost: number | null; inventory_transaction_id: string | null
  remarks: string | null; source_document_type: string | null; source_line_id: string | null
  created_by: string | null; updated_by: string | null
  created_at: string; updated_at: string
}

type CustomerMaster = {
  id: string; registered_name: string; tin: string; tin_branch_code: string | null
  registered_address: string; delivery_address: string | null
  contact_person: string | null; email: string | null; phone_number: string | null
  default_tax_type: string; is_subject_to_cwt: boolean
  default_terms_id: string | null; credit_limit: number | null
  customer_code: string; customer_group: string | null; business_style: string | null
  trade_name: string | null; created_at: string | null; is_active: boolean | null
}

type AccountRef = { code: string; name: string }
type ItemRef = { code: string; description: string; notes: string | null }
type UomRef = { code: string; description: string }
type VatRef = { code: string; classification: string; rate: number }
type DepartmentRef = { code: string; name: string }
type CostCenterRef = { code: string; name: string }
type WarehouseRef = { code: string; name: string }
type EmployeeRef = { number: string; name: string }
type VoidReason = { id: string; code: string; description: string }
type Collection = { paid: number; cwt: number; balance: number; receiptCount: number; status: string | null }
type ApprovalRow = {
  id: string; status: string; required_approver_type: string
  required_approver_id: string | null; actual_approver_id: string | null
  step_sequence: number; submitted_at: string; acted_at: string | null
  remarks: string | null
}
type RecentInvoice = {
  id: string; si_number: string; date: string; due_date: string | null
  total_amount: number; status: string
}
type RecentPayment = {
  id: string; receipt_number: string; receipt_date: string
  total_amount: number; total_cwt: number; status: string
}
type AgingBalance = {
  invoice_id: string; si_number: string; invoice_date: string; due_date: string | null
  original_amount: number; balance_due: number; days_overdue: number
}

const statusToShared: Record<SIStatus, string> = {
  draft: 'draft', approved: 'approved', posted: 'posted', cancelled: 'error',
}
const STATUS_LABEL: Record<SIStatus, string> = {
  draft: 'Draft', approved: 'Approved', posted: 'Posted', cancelled: 'Voided',
}
const TAX_TYPE_LABEL: Record<string, string> = {
  vat_registered: 'VAT registered', non_vat: 'Non-VAT', vat_exempt: 'VAT exempt', zero_rated: 'Zero-rated',
}
const formatDateTime = (v?: string | null) => (v ? new Date(v).toLocaleString('en-PH') : 'Not recorded')
const num = (v: unknown) => Number(v ?? 0)
const userText = (id?: string | null) => id ? 'Recorded user' : '—'
const userDisplay = (id?: string | null) => id ? <span title={id}>Recorded user</span> : '—'
const erpTabSection = (title: string, description: ReactNode, children: ReactNode) => (
  <section className="pxl-transaction-card pxl-transaction-card--raised p-3 space-y-2">
    <ErpSectionHeader title={title} description={description} className="pb-2 border-b border-gray-100" />
    {children}
  </section>
)

export default function SalesInvoiceDocumentPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { companyId } = useAppCtx()

  const [si, setSi] = useState<SIRow | null>(null)
  const [lines, setLines] = useState<LineRow[]>([])
  const [accounts, setAccounts] = useState<Record<string, AccountRef>>({})
  const [items, setItems] = useState<Record<string, ItemRef>>({})
  const [uoms, setUoms] = useState<Record<string, UomRef>>({})
  const [vatCodes, setVatCodes] = useState<Record<string, VatRef>>({})
  const [departments, setDepartments] = useState<Record<string, DepartmentRef>>({})
  const [costCenters, setCostCenters] = useState<Record<string, CostCenterRef>>({})
  const [warehouses, setWarehouses] = useState<Record<string, WarehouseRef>>({})
  const [employees, setEmployees] = useState<Record<string, EmployeeRef>>({})
  const [branchName, setBranchName] = useState('')
  const [seriesName, setSeriesName] = useState('')
  const [termsName, setTermsName] = useState<Record<string, string>>({})
  const [customer, setCustomer] = useState<CustomerMaster | null>(null)
  const [customerOutstanding, setCustomerOutstanding] = useState<number | null>(null)
  const [lastPayment, setLastPayment] = useState<{ date: string; amount: number } | null>(null)
  const [recentInvoices, setRecentInvoices] = useState<RecentInvoice[]>([])
  const [recentPayments, setRecentPayments] = useState<RecentPayment[]>([])
  const [agingBalances, setAgingBalances] = useState<AgingBalance[]>([])
  const [collection, setCollection] = useState<Collection>({ paid: 0, cwt: 0, balance: 0, receiptCount: 0, status: null })
  const [approvals, setApprovals] = useState<ApprovalRow[]>([])
  const [relatedRows, setRelatedRows] = useState<RelatedDocRow[]>([])
  const [accountingImpact, setAccountingImpact] = useState<ServerGLImpact | null>(null)
  const [voidReasons, setVoidReasons] = useState<VoidReason[]>([])
  const [selectedLineId, setSelectedLineId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [notFound, setNotFound] = useState(false)

  // Lifecycle-action state
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState('')
  const [showVoid, setShowVoid] = useState(false)
  const [voidReason, setVoidReason] = useState('')
  const [voidMemo, setVoidMemo] = useState('')

  const load = useCallback(async () => {
    if (!id) return
    setLoading(true); setNotFound(false)
    const { data: head } = await supabase.from('sales_invoices').select('*').eq('id', id).maybeSingle()
    if (!head) { setNotFound(true); setLoading(false); return }
    const inv = head as unknown as SIRow
    setSi(inv)

    const todayIso = new Date().toISOString().slice(0, 10)
    const [lineRes, accRes, itemRes, uomRes, vatRes, deptRes, ccRes, whRes, empRes, brRes, termRes, custRes, jeRes, rlRes, reasonRes, apprRes, seriesRes, customerInvoiceRes, customerReceiptRes, agingRes, impactRes] = await Promise.all([
      supabase.from('sales_invoice_lines').select('*').eq('sales_invoice_id', id).order('line_number'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', inv.company_id),
      supabase.from('items').select('id,item_code,description,description_long').eq('company_id', inv.company_id),
      supabase.from('units_of_measure').select('id,uom_code,description').eq('company_id', inv.company_id),
      supabase.from('vat_codes').select('id,vat_code,vat_classification,tax_codes(rate)'),
      supabase.from('departments').select('id,department_code,department_name').eq('company_id', inv.company_id),
      supabase.from('cost_centers').select('id,cost_center_code,cost_center_name').eq('company_id', inv.company_id),
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', inv.company_id),
      supabase.from('employees').select('id,employee_number,first_name,last_name').eq('company_id', inv.company_id),
      supabase.from('branches').select('id,branch_name').eq('id', inv.branch_id).maybeSingle(),
      supabase.from('payment_terms').select('id,term_name').eq('company_id', inv.company_id),
      inv.customer_id ? supabase.from('customers').select('*').eq('id', inv.customer_id).maybeSingle() : Promise.resolve({ data: null }),
      supabase.from('journal_entries').select('id,je_number,je_date,status,total_debit')
        .eq('company_id', inv.company_id).eq('reference_doc_type', 'SI').eq('reference_doc_id', inv.id).order('je_date'),
      supabase.from('receipt_lines').select('receipt_id,payment_amount,cwt_amount').eq('invoice_id', inv.id),
      supabase.from('void_reason_codes').select('id,code,description').eq('is_active', true).order('code'),
      supabase.from('approval_instances').select('*').eq('source_document_id', inv.id).order('step_sequence'),
      supabase.from('number_series').select('prefix,number_length,reset_frequency').eq('company_id', inv.company_id).eq('branch_id', inv.branch_id).eq('document_code', 'SI').eq('is_active', true).limit(1).maybeSingle(),
      supabase.from('sales_invoices').select('id,si_number,date,due_date,total_amount,status').eq('company_id', inv.company_id).eq('customer_id', inv.customer_id).order('date', { ascending: false }),
      supabase.from('receipts').select('id,receipt_number,receipt_date,total_amount,total_cwt,status').eq('company_id', inv.company_id).eq('customer_id', inv.customer_id).eq('status', 'posted').order('receipt_date', { ascending: false }),
      supabase.rpc('fn_ar_aging_asof', { p_company_id: inv.company_id, p_as_of: todayIso, p_customer_id: inv.customer_id }),
      supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'SI', p_source_doc_id: inv.id, p_posting_date: inv.date }),
    ])

    setLines((lineRes.data ?? []) as unknown as LineRow[])
    const map: Record<string, AccountRef> = {}
    for (const a of accRes.data ?? []) map[a.id] = { code: a.account_code, name: a.account_name }
    setAccounts(map)
    const itemMap: Record<string, ItemRef> = {}
    for (const item of itemRes.data ?? []) itemMap[item.id] = { code: item.item_code, description: item.description, notes: item.description_long }
    setItems(itemMap)
    const uomMap: Record<string, UomRef> = {}
    for (const uom of uomRes.data ?? []) uomMap[uom.id] = { code: uom.uom_code, description: uom.description }
    setUoms(uomMap)
    const vatMap: Record<string, VatRef> = {}
    for (const vat of vatRes.data ?? []) {
      const tax = Array.isArray(vat.tax_codes) ? vat.tax_codes[0] : vat.tax_codes
      vatMap[vat.id] = { code: vat.vat_code, classification: vat.vat_classification, rate: Number(tax?.rate ?? 0) }
    }
    setVatCodes(vatMap)
    const departmentMap: Record<string, DepartmentRef> = {}
    for (const department of deptRes.data ?? []) departmentMap[department.id] = { code: department.department_code, name: department.department_name }
    setDepartments(departmentMap)
    const costCenterMap: Record<string, CostCenterRef> = {}
    for (const costCenter of ccRes.data ?? []) costCenterMap[costCenter.id] = { code: costCenter.cost_center_code, name: costCenter.cost_center_name }
    setCostCenters(costCenterMap)
    const warehouseMap: Record<string, WarehouseRef> = {}
    for (const warehouse of whRes.data ?? []) warehouseMap[warehouse.id] = { code: warehouse.warehouse_code, name: warehouse.warehouse_name }
    setWarehouses(warehouseMap)
    const employeeMap: Record<string, EmployeeRef> = {}
    for (const employee of empRes.data ?? []) {
      employeeMap[employee.id] = { number: employee.employee_number, name: `${employee.first_name} ${employee.last_name}` }
    }
    setEmployees(employeeMap)
    setBranchName((brRes.data as { branch_name?: string } | null)?.branch_name ?? '')
    const series = seriesRes.data as { prefix?: string | null; number_length?: number; reset_frequency?: string } | null
    setSeriesName(series ? `${series.prefix || 'SI'} · ${series.number_length ?? 6} digits · ${series.reset_frequency ?? 'never'} reset` : '')
    const tmap: Record<string, string> = {}
    for (const t of termRes.data ?? []) tmap[t.id] = t.term_name
    setTermsName(tmap)
    setCustomer((custRes.data as CustomerMaster | null) ?? null)
    setAccountingImpact(impactRes.error ? null : impactRes.data as unknown as ServerGLImpact)
    setVoidReasons((reasonRes.data ?? []) as VoidReason[])
    setApprovals((apprRes.data ?? []) as ApprovalRow[])

    const invoiceRows = ((customerInvoiceRes.data ?? []) as RecentInvoice[])
    setRecentInvoices(invoiceRows.slice(0, 5))
    const postedCustomerReceipts = ((customerReceiptRes.data ?? []) as RecentPayment[]).filter(row => row.status === 'posted')
    setRecentPayments(postedCustomerReceipts.slice(0, 5))
    const customerAgingRows = ((agingRes.data ?? []) as Array<Record<string, unknown>>).map(row => ({
      invoice_id: String(row.invoice_id),
      si_number: String(row.si_number),
      invoice_date: String(row.invoice_date),
      due_date: row.due_date ? String(row.due_date) : null,
      original_amount: num(row.original_amount),
      balance_due: num(row.balance_due),
      days_overdue: num(row.days_overdue),
    }))
    setAgingBalances(customerAgingRows)
    const customerReceiptTotal = postedCustomerReceipts.reduce((sum, row) => sum + num(row.total_amount) + num(row.total_cwt), 0)
    const customerInvoiceTotal = invoiceRows.filter(row => row.status === 'posted').reduce((sum, row) => sum + num(row.total_amount), 0)
    const outstandingFromAging = customerAgingRows.reduce((sum, row) => sum + num(row.balance_due), 0)
    setCustomerOutstanding(agingRes.error ? Math.max(0, customerInvoiceTotal - customerReceiptTotal) : outstandingFromAging)
    const latestReceipt = postedCustomerReceipts[0]
    setLastPayment(latestReceipt ? { date: latestReceipt.receipt_date, amount: num(latestReceipt.total_amount) + num(latestReceipt.total_cwt) } : null)

    // Collection: sum posted-receipt applications against this invoice.
    const rls = (rlRes.data ?? []) as Array<{ receipt_id: string; payment_amount: number; cwt_amount: number }>
    let paid = 0, cwtColl = 0
    const receiptIds = [...new Set(rls.map(r => r.receipt_id))]
    const postedReceiptsById = new Map(postedCustomerReceipts.map(receipt => [receipt.id, receipt]))
    const appliedByReceipt = new Map<string, { payment: number; cwt: number }>()
    for (const rl of rls) {
      if (!postedReceiptsById.has(rl.receipt_id)) continue
      paid += num(rl.payment_amount)
      cwtColl += num(rl.cwt_amount)
      const current = appliedByReceipt.get(rl.receipt_id) ?? { payment: 0, cwt: 0 }
      current.payment += num(rl.payment_amount)
      current.cwt += num(rl.cwt_amount)
      appliedByReceipt.set(rl.receipt_id, current)
    }
    const linkedReceipts = receiptIds
      .map(receiptId => postedReceiptsById.get(receiptId))
      .filter((receipt): receipt is RecentPayment => Boolean(receipt))
    const balance = num(inv.total_amount) - paid - cwtColl
    const collStatus = inv.status !== 'posted' ? null
      : balance <= 0.005 && (paid + cwtColl) > 0 ? 'Paid'
      : (paid + cwtColl) > 0 ? 'Partially Paid' : 'Open'
    setCollection({ paid, cwt: cwtColl, balance, receiptCount: receiptIds.length, status: collStatus })

    // Related-document chain (§16).
    const posted = inv.status === 'posted'
    const rows: RelatedDocRow[] = [
      { key: 'quo', relationship: 'Source Quotation', docType: 'Quotation', direction: 'upstream', note: 'Not linked on this document' },
      { key: 'so', relationship: 'Source Sales Order', docType: 'Sales Order', direction: 'upstream', note: 'Not linked on this document' },
      { key: 'dr', relationship: 'Source Delivery Receipt', docType: 'Delivery Receipt', direction: 'upstream', note: 'Not linked on this document' },
      { key: 'si', relationship: 'This document', docType: 'Sales Invoice', direction: 'current', number: inv.si_number, date: inv.date, status: statusToShared[inv.status], amount: num(inv.total_amount), appliedAmount: paid + cwtColl, openBalance: balance },
      ...linkedReceipts.map(receipt => {
        const application = appliedByReceipt.get(receipt.id) ?? { payment: 0, cwt: 0 }
        const applied = application.payment + application.cwt
        return {
          key: `or-${receipt.id}`,
          relationship: 'Collection',
          docType: 'Official Receipt',
          direction: 'downstream' as const,
          number: receipt.receipt_number,
          date: receipt.receipt_date,
          status: 'posted',
          amount: num(receipt.total_amount) + num(receipt.total_cwt),
          appliedAmount: applied,
          openBalance: balance,
          href: '/receipts',
        }
      }),
      ...(linkedReceipts.length === 0
        ? [{ key: 'or', relationship: 'Collection', docType: 'Official Receipt', direction: 'downstream' as const, action: posted ? { label: 'Create Receipt', href: '/receipts' } : null }]
        : []),
      { key: 'cm', relationship: 'Adjustment', docType: 'Credit Memo', direction: 'downstream', action: posted ? { label: 'Create Credit Memo', href: '/credit-memos' } : null },
      { key: 'dm', relationship: 'Adjustment', docType: 'Debit Memo', direction: 'downstream' },
      { key: 'ret', relationship: 'Return', docType: 'Customer Return', direction: 'downstream' },
      ...(jeRes.data ?? []).map(je => ({
        key: `je-${je.id}`,
        relationship: je.status === 'reversed' ? 'Reversal Journal' : 'Journal Entry',
        docType: 'Journal Entry', direction: 'downstream' as const,
        number: je.je_number, date: je.je_date, status: je.status, amount: num(je.total_debit),
        href: `/accounting-trace?sourceType=SI&sourceId=${inv.id}`,
      })),
      ...((jeRes.data ?? []).length === 0
        ? [{ key: 'je-none', relationship: 'Journal Entry', docType: 'Journal Entry', direction: 'downstream' as const, note: posted ? 'Not found' : 'Posts on approval → posting' }]
        : []),
    ]
    setRelatedRows(rows)
    setLoading(false)
  }, [id])

  useEffect(() => { load() }, [load])

  const readiness = useTransactionReadiness({
    companyId, branchId: si?.branch_id ?? '', documentCode: 'SI',
    postingDate: si?.date ?? '', requiredConfig: SI_REQUIRED_CONFIG,
  })

  const backToList = () => navigate('/sales-invoices')

  if (loading) return <div className="py-10 text-center text-sm text-gray-400">Loading Sales Invoice…</div>
  if (notFound || !si) {
    return (
      <div className="py-10">
        <EmptyState title="Sales Invoice not found"
          description="It may have been removed, or belongs to a different company than the one currently selected."
          action={<button onClick={backToList} className="px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">← Back to Sales Invoices</button>} />
      </div>
    )
  }

  // ── Lifecycle actions (server enforces role/SoD; UI gates by status) ──
  const runAction = async (fn: 'fn_approve_sales_invoice' | 'fn_post_sales_invoice' | 'fn_revert_si_to_draft', label: string) => {
    setBusy(true); setActionError('')
    const { error } = await supabase.rpc(fn, { p_invoice_id: si.id })
    setBusy(false)
    if (error) { setActionError(`${label} failed: ${error.message}`); return }
    await load()
  }
  const doVoid = async () => {
    if (!voidReason) return
    setBusy(true); setActionError('')
    const { error } = await supabase.rpc('fn_void_sales_invoice', { p_invoice_id: si.id, p_void_reason_id: voidReason, p_memo: voidMemo || undefined })
    setBusy(false)
    if (error) { setActionError(`Void failed: ${error.message}`); return }
    setShowVoid(false); setVoidReason(''); setVoidMemo(''); await load()
  }

  // ── Derived figures ─────────────────────────────────────────
  const netOfVat = num(si.total_taxable_amount) + num(si.total_zero_rated_amount) + num(si.total_exempt_amount)
  const discounts = lines.reduce((s, l) => s + num(l.discount_amount), 0)
  const subtotal = netOfVat + discounts
  const inventoryCost = lines.reduce((sum, line) => sum + num(line.inventory_cost), 0)
  const grossProfit = netOfVat - inventoryCost
  const grossMargin = netOfVat > 0 ? (grossProfit / netOfVat) * 100 : null
  const cwt = num(si.cwt_amount_expected)
  const impactLines = accountingImpact?.lines ?? []
  const commercialImpactLines = impactLines.filter(line => line.impact_group !== 'INVENTORY')
  const inventoryImpactLines = impactLines.filter(line => line.impact_group === 'INVENTORY')
  const commercialGlDebit = commercialImpactLines.reduce((sum, line) => sum + num(line.debit), 0)
  const commercialGlCredit = commercialImpactLines.reduce((sum, line) => sum + num(line.credit), 0)
  const inventoryGlDebit = inventoryImpactLines.reduce((sum, line) => sum + num(line.debit), 0)
  const inventoryGlCredit = inventoryImpactLines.reduce((sum, line) => sum + num(line.credit), 0)
  const combinedGlDebit = accountingImpact ? num(accountingImpact.total_debit) : commercialGlDebit + inventoryGlDebit
  const combinedGlCredit = accountingImpact ? num(accountingImpact.total_credit) : commercialGlCredit + inventoryGlCredit
  const combinedGlDifference = combinedGlDebit - combinedGlCredit
  const inventoryItemCount = lines.filter(line => line.warehouse_id || line.inventory_transaction_id || num(line.inventory_cost) > 0).length
  const quantityIssued = lines
    .filter(line => line.warehouse_id || line.inventory_transaction_id || num(line.inventory_cost) > 0)
    .reduce((sum, line) => sum + num(line.quantity), 0)
  const withholdingInfo: WithholdingInfo | null = cwt > 0 ? {
    withholdingType: 'Expected CWT',
    atc: null,
    rate: null,
    base: netOfVat,
    amount: cwt,
    expectedNetCollectible: num(si.total_amount) - cwt,
    recognitionEvent: 'Receipt or payment application',
    status: 'Informational only',
  } : null
  const lockLabel = si.status === 'draft' ? 'Editable' : 'Frozen'
  const headerStatus = si.status === 'cancelled' ? 'voided' : si.status
  const headerStatusLabel = STATUS_LABEL[si.status]

  // ── Workflow model (rendered only in the Workflow tab) ──────
  const salesSteps = [
    { key: 'draft', label: 'Draft' }, { key: 'approved', label: 'Approved' },
    { key: 'posted', label: 'Posted' }, { key: 'partially_paid', label: 'Partially Paid' }, { key: 'paid', label: 'Paid' },
  ]
  let workflow: { steps: { key: string; label: string }[]; currentKey: string }
  if (si.status === 'cancelled') workflow = { steps: [{ key: 'draft', label: 'Draft' }, { key: 'voided', label: 'Voided' }], currentKey: 'voided' }
  else if (si.status === 'posted' && collection.status === 'Paid') workflow = { steps: salesSteps, currentKey: 'paid' }
  else if (si.status === 'posted' && collection.status === 'Partially Paid') workflow = { steps: salesSteps, currentKey: 'partially_paid' }
  else workflow = { steps: salesSteps, currentKey: si.status }

  // ── Toolbar — status-aware ──────────────────────────────────
  const actions: ToolbarAction[] = []
  if (si.status === 'draft') {
    actions.push({ key: 'approve', label: 'Submit', variant: 'primary', onClick: () => runAction('fn_approve_sales_invoice', 'Approve'), disabled: busy })
    actions.push({ key: 'edit', label: 'Edit', group: 'more', onClick: () => navigate(`/sales-invoices/${si.id}/edit`), disabled: busy, title: 'Open the editable Sales Invoice form' })
  }
  if (si.status === 'approved') {
    actions.push({ key: 'post', label: 'Post', variant: 'primary', onClick: () => runAction('fn_post_sales_invoice', 'Post'), disabled: busy })
    actions.push({ key: 'revert', label: 'Return to Draft', group: 'more', onClick: () => runAction('fn_revert_si_to_draft', 'Return to draft'), disabled: busy })
  }
  if (si.status === 'posted') {
    actions.push({ key: 'receipt', label: 'Create Receipt', variant: 'primary', onClick: () => navigate('/receipts') })
    actions.push({ key: 'cm', label: 'Create Credit Memo', group: 'more', onClick: () => navigate('/credit-memos') })
    actions.push({ key: 'void', label: 'Void', group: 'more', variant: 'danger', onClick: () => setShowVoid(true), disabled: busy })
  }
  actions.push({ key: 'print', label: 'Print', onClick: () => window.print() })
  actions.push({
    key: 'email', label: 'Email', onClick: () => {
      const subject = encodeURIComponent(`Sales Invoice ${si.si_number}`)
      const body = encodeURIComponent(`Sales Invoice ${si.si_number}\nAmount: ${si.currency_code} ${num(si.total_amount).toFixed(2)}`)
      window.location.href = `mailto:${customer?.email || ''}?subject=${subject}&body=${body}`
    },
  })
  actions.push({ key: 'dm', label: 'Create Debit Memo', group: 'more', onClick: () => navigate('/debit-memos'), disabled: si.status !== 'posted' })
  actions.push({ key: 'customer', label: 'Open Customer', group: 'more', onClick: () => navigate(`/customers?customerId=${si.customer_id}`) })
  actions.push({ key: 'ledger', label: 'View Ledger', group: 'more', onClick: () => navigate(`/ar-aging?tab=ledger&customerId=${si.customer_id}`) })
  actions.push({ key: 'tax-ledger', label: 'View Tax Ledger', group: 'more', onClick: () => {
    const date = new Date(`${si.date}T00:00:00`)
    navigate(`/sales-tax-review?sourceId=${si.id}&month=${date.getMonth() + 1}&year=${date.getFullYear()}`)
  } })
  actions.push({ key: 'einvoice', label: 'Generate E-Invoice', group: 'more', onClick: () => {}, disabled: true, title: 'E-invoice provider and credentials are not configured.' })
  actions.push({ key: 'duplicate', label: 'Duplicate', group: 'more', onClick: () => {}, disabled: true, title: 'Document duplication is not configured yet.' })
  actions.push({ key: 'je', label: 'Open Journal Entry', group: 'more', onClick: () => navigate(`/accounting-trace?sourceType=SI&sourceId=${si.id}`) })
  actions.push({ key: 'refresh', label: 'Refresh', group: 'more', onClick: load, disabled: busy })

  // ── Primary Information (§5) ─────────────────────────────────
  const termLabel = (tid: string | null) => (tid && termsName[tid]) || '—'
  const departmentLabel = (id?: string | null) => id && departments[id] ? `${departments[id].code} ${departments[id].name}` : null
  const costCenterLabel = (id?: string | null) => id && costCenters[id] ? `${costCenters[id].code} ${costCenters[id].name}` : null
  const warehouseLabel = (id?: string | null) => id && warehouses[id] ? `${warehouses[id].code} ${warehouses[id].name}` : null
  const employeeLabel = (id?: string | null) => id && employees[id] ? `${employees[id].number} ${employees[id].name}` : null
  const assignedContextFields = [
    { label: 'Account Owner', value: employeeLabel(si.account_owner_id) },
    { label: 'Salesperson', value: employeeLabel(si.salesperson_id) },
    { label: 'Department', value: departmentLabel(si.department_id) },
    { label: 'Cost Center', value: costCenterLabel(si.cost_center_id) },
    { label: 'Default Warehouse', value: warehouseLabel(si.warehouse_id) },
  ].filter(field => field.value)
  const availableCredit = customer?.credit_limit != null && customerOutstanding != null
    ? num(customer.credit_limit) - customerOutstanding
    : null
  const openCustomer = () => navigate(`/customers?customerId=${si.customer_id}`)
  const customerLink = (
    <button onClick={openCustomer} className="text-blue-700 hover:underline text-left">
      {si.customer_name_snapshot || customer?.registered_name || '—'}
    </button>
  )
  const documentFields: NonNullable<InfoGroup['fields']> = [
    { label: 'Invoice Date', value: <DateCell date={si.date} /> },
    { label: 'Due Date', value: si.due_date ? <DateCell date={si.due_date} /> : '—' },
    { label: 'Branch', value: branchName || '—' },
    { label: 'Currency', value: si.currency_code },
    { label: 'Payment Terms', value: termLabel(si.payment_terms_id), provenance: 'from Customer / document' },
    { label: 'External Reference', value: si.reference || 'Not linked' },
  ]
  const primaryGroups: InfoGroup[] = [
    {
      key: 'doc', title: 'Document Information', fields: documentFields,
    },
    {
      key: 'cust', title: 'Customer Information', fields: [
        { label: 'Customer', value: customerLink, provenance: 'invoice customer snapshot / opens Customer master' },
        { label: 'Customer Code', value: customer?.customer_code || 'Not stored on invoice snapshot', provenance: 'current Customer master; snapshot field not stored' },
        { label: 'TIN', value: si.customer_tin_snapshot ? normalizePhTin(si.customer_tin_snapshot) : 'Not stored', provenance: 'invoice TIN snapshot' },
        { label: 'TIN Branch', value: si.customer_tin_snapshot ? getPhTinBranch(si.customer_tin_snapshot) : 'Not stored', provenance: 'invoice TIN snapshot' },
        { label: 'VAT Classification', value: customer ? (TAX_TYPE_LABEL[customer.default_tax_type] ?? customer.default_tax_type) : 'Not stored on invoice snapshot', provenance: 'current Customer master; snapshot field not stored' },
        { label: 'Business Style', value: customer?.business_style || 'Not stored on invoice snapshot', provenance: 'current Customer master; snapshot field not stored' },
      ],
    },
    {
      key: 'ctx', title: 'Sales Context',
      content: assignedContextFields.length > 0 ? (
        <div className="grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
          {assignedContextFields.map(field => (
            <div key={field.label}>
              <div className="text-[10px] font-medium uppercase tracking-wide text-gray-400">{field.label}</div>
              <div className="mt-0.5 text-xs text-gray-700">{field.value}</div>
            </div>
          ))}
        </div>
      ) : (
        <CompactEmptyState>No operational dimensions assigned.</CompactEmptyState>
      ),
    },
  ]
  const primaryInfo = <PrimaryInformationPanel groups={primaryGroups} />

  // ── Lines tab + Line Detail Panel ───────────────────────────
  const accountLabel = (accId: string | null) => {
    if (!accId) return <span className="text-amber-600">Unmapped</span>
    const a = accounts[accId]
    return a ? <span title={a.name}>{a.code}</span> : <span className="text-gray-400">—</span>
  }
  const emptyLineValue = <span className="text-gray-300">—</span>
  const lineItemCode = (line: LineRow) => line.item_id ? items[line.item_id]?.code ?? '—' : ''
  const lineItemDescription = (line: LineRow) => line.item_id ? items[line.item_id]?.description ?? '—' : ''
  const lineUom = (line: LineRow) => line.uom_id ? uoms[line.uom_id]?.code ?? '—' : ''
  const lineVatCode = (line: LineRow) => line.vat_code_id ? vatCodes[line.vat_code_id]?.code ?? '—' : ''
  const lineVatRate = (line: LineRow) => line.vat_code_id ? num(vatCodes[line.vat_code_id]?.rate) : 0
  const lineWarehouse = (line: LineRow) => warehouseLabel(line.warehouse_id) || ''
  const lineDepartment = (line: LineRow) => departmentLabel(line.department_id || si.department_id) || ''
  const lineCostCenter = (line: LineRow) => costCenterLabel(line.cost_center_id || si.cost_center_id) || ''
  const lineRevenueAccount = (line: LineRow) => {
    if (!line.revenue_account_id) return 'Unmapped'
    const account = accounts[line.revenue_account_id]
    return account ? `${account.code} ${account.name}` : ''
  }
  const linePostingRule = (line: LineRow) => line.revenue_account_id ? 'Line revenue account' : 'Unmapped revenue account'
  const lineColumns: LineColumn<LineRow>[] = [
    { key: 'no', header: '#', group: 'system', pinned: true, defaultWidth: 56, sortValue: line => line.line_number, filterValue: line => line.line_number, exportValue: line => line.line_number, render: line => <span className="text-gray-400">{line.line_number}</span> },
    { key: 'item_code', header: 'Item Code', group: 'sales', pinned: true, defaultWidth: 110, sortValue: lineItemCode, filterValue: lineItemCode, exportValue: lineItemCode, render: line => line.item_id ? <span className="font-mono font-medium">{items[line.item_id]?.code ?? '—'}</span> : emptyLineValue },
    { key: 'item_desc', header: 'Item Description', group: 'sales', defaultWidth: 160, sortValue: lineItemDescription, filterValue: lineItemDescription, exportValue: lineItemDescription, render: line => line.item_id ? (items[line.item_id]?.description ?? '—') : emptyLineValue },
    { key: 'desc', header: 'Description', group: 'sales', pinned: true, defaultWidth: 220, sortValue: line => line.description, filterValue: line => line.description, exportValue: line => line.description, render: line => <span className="text-gray-900">{line.description}</span> },
    { key: 'qty', header: 'Qty', group: 'sales', align: 'right', defaultWidth: 84, sortValue: line => num(line.quantity), filterValue: line => num(line.quantity), exportValue: line => num(line.quantity), render: line => <span className="font-mono tabular-nums text-gray-700">{num(line.quantity)}</span> },
    { key: 'uom', header: 'UOM', group: 'inventory', defaultWidth: 84, sortValue: lineUom, filterValue: lineUom, exportValue: lineUom, render: line => line.uom_id ? <span title={uoms[line.uom_id]?.description}>{uoms[line.uom_id]?.code ?? '—'}</span> : emptyLineValue },
    { key: 'warehouse', header: 'Warehouse', group: 'inventory', defaultWidth: 130, sortValue: lineWarehouse, filterValue: lineWarehouse, exportValue: lineWarehouse, render: line => lineWarehouse(line) || emptyLineValue },
    { key: 'department', header: 'Department', group: 'dimensions', defaultWidth: 130, sortValue: lineDepartment, filterValue: lineDepartment, exportValue: lineDepartment, render: line => lineDepartment(line) || emptyLineValue },
    { key: 'cost_center', header: 'Cost Center', group: 'dimensions', defaultWidth: 130, sortValue: lineCostCenter, filterValue: lineCostCenter, exportValue: lineCostCenter, render: line => lineCostCenter(line) || emptyLineValue },
    { key: 'price', header: 'Unit Price', group: 'sales', align: 'right', defaultWidth: 112, sortValue: line => num(line.unit_price), filterValue: line => num(line.unit_price), exportValue: line => num(line.unit_price), render: line => <AmountCell amount={num(line.unit_price)} /> },
    { key: 'disc_pct', header: 'Discount %', group: 'sales', align: 'right', defaultWidth: 104, sortValue: line => num(line.discount_percent), filterValue: line => num(line.discount_percent), exportValue: line => num(line.discount_percent), render: line => <span className="font-mono">{num(line.discount_percent)}%</span> },
    { key: 'disc_amt', header: 'Discount Amount', group: 'sales', align: 'right', defaultWidth: 132, sortValue: line => num(line.discount_amount), filterValue: line => num(line.discount_amount), exportValue: line => num(line.discount_amount), render: line => <AmountCell amount={num(line.discount_amount)} /> },
    { key: 'net', header: 'Net', group: 'sales', align: 'right', defaultWidth: 112, sortValue: line => num(line.net_amount), filterValue: line => num(line.net_amount), exportValue: line => num(line.net_amount), render: line => <AmountCell amount={num(line.net_amount)} /> },
    { key: 'tax_base', header: 'Tax Base', group: 'tax', align: 'right', defaultWidth: 112, sortValue: line => num(line.net_amount), filterValue: line => num(line.net_amount), exportValue: line => num(line.net_amount), render: line => <AmountCell amount={num(line.net_amount)} /> },
    { key: 'vat_code', header: 'VAT Code', group: 'tax', defaultWidth: 104, sortValue: lineVatCode, filterValue: lineVatCode, exportValue: lineVatCode, render: line => line.vat_code_id ? <span className="font-mono">{vatCodes[line.vat_code_id]?.code ?? '—'}</span> : emptyLineValue },
    { key: 'vat_pct', header: 'VAT %', group: 'tax', align: 'right', defaultWidth: 80, sortValue: lineVatRate, filterValue: lineVatRate, exportValue: lineVatRate, render: line => line.vat_code_id ? <span className="font-mono">{num(vatCodes[line.vat_code_id]?.rate)}%</span> : emptyLineValue },
    { key: 'vat_amt', header: 'VAT Amount', group: 'tax', align: 'right', defaultWidth: 116, sortValue: line => num(line.vat_amount), filterValue: line => num(line.vat_amount), exportValue: line => num(line.vat_amount), render: line => <AmountCell amount={num(line.vat_amount)} /> },
    { key: 'tax_class', header: 'Tax Classification', group: 'tax', defaultWidth: 136, sortValue: line => line.vat_code_id ? vatCodes[line.vat_code_id]?.classification ?? '' : '', filterValue: line => line.vat_code_id ? vatCodes[line.vat_code_id]?.classification ?? '' : '', exportValue: line => line.vat_code_id ? vatCodes[line.vat_code_id]?.classification ?? '' : '', render: line => line.vat_code_id ? vatCodes[line.vat_code_id]?.classification ?? '—' : emptyLineValue },
    { key: 'atc', header: 'ATC', group: 'tax', defaultWidth: 82, render: () => emptyLineValue },
    { key: 'ewt_code', header: 'EWT Code', group: 'withholding', defaultWidth: 100, render: () => emptyLineValue },
    { key: 'ewt_amt', header: 'EWT Amount', group: 'withholding', align: 'right', defaultWidth: 112, sortValue: () => 0, filterValue: () => 0, exportValue: () => 0, render: () => emptyLineValue },
    { key: 'total', header: 'Line Total', group: 'sales', align: 'right', defaultWidth: 120, sortValue: line => num(line.total_amount), filterValue: line => num(line.total_amount), exportValue: line => num(line.total_amount), render: line => <span className="font-semibold text-gray-900"><AmountCell amount={num(line.total_amount)} /></span> },
    { key: 'acct', header: 'Revenue Account', group: 'accounting', defaultWidth: 150, sortValue: lineRevenueAccount, filterValue: lineRevenueAccount, exportValue: lineRevenueAccount, render: line => <span className="font-mono text-gray-600">{accountLabel(line.revenue_account_id)}</span> },
    { key: 'inventory_cost', header: 'Inventory Cost', group: 'inventory', align: 'right', defaultWidth: 124, sortValue: line => num(line.inventory_cost), filterValue: line => num(line.inventory_cost), exportValue: line => num(line.inventory_cost), render: line => line.inventory_cost != null ? <AmountCell amount={num(line.inventory_cost)} /> : emptyLineValue },
    { key: 'inventory_tx', header: 'Inventory Tx', group: 'inventory', defaultWidth: 132, sortValue: line => line.inventory_transaction_id || '', filterValue: line => line.inventory_transaction_id || '', exportValue: line => line.inventory_transaction_id || '', render: line => line.inventory_transaction_id ? <span className="font-mono">{line.inventory_transaction_id.slice(0, 8)}...</span> : emptyLineValue },
    { key: 'branch', header: 'Branch', group: 'dimensions', defaultWidth: 130, sortValue: () => branchName, filterValue: () => branchName, exportValue: () => branchName, render: () => branchName || '—' },
    { key: 'remarks', header: 'Remarks', group: 'reference', defaultWidth: 120, sortValue: line => line.remarks || '', filterValue: line => line.remarks || '', exportValue: line => line.remarks || '', render: line => line.remarks || emptyLineValue },
    { key: 'reference', header: 'External Reference', group: 'reference', defaultWidth: 150, sortValue: () => si.reference || '', filterValue: () => si.reference || '', exportValue: () => si.reference || '', render: () => si.reference || emptyLineValue },
    { key: 'source_doc', header: 'Source Document', group: 'audit', defaultWidth: 140, sortValue: () => si.reference || '', filterValue: () => si.reference || '', exportValue: () => si.reference || '', render: () => si.reference || emptyLineValue },
    { key: 'journal_entry', header: 'Journal Entry', group: 'audit', defaultWidth: 130, sortValue: () => si.journal_entry_id || '', filterValue: () => si.journal_entry_id ? 'Linked Journal Entry' : '', exportValue: () => si.journal_entry_id ? 'Linked Journal Entry' : '', render: () => si.journal_entry_id ? <button type="button" onClick={() => navigate(`/accounting-trace?sourceType=SI&sourceId=${si.id}`)} className="text-blue-700 hover:underline">Open trace</button> : emptyLineValue },
    { key: 'posting_rule', header: 'Posting Rule', group: 'audit', defaultWidth: 160, sortValue: linePostingRule, filterValue: linePostingRule, exportValue: linePostingRule, render: line => linePostingRule(line) },
    { key: 'created_by', header: 'Created By', group: 'audit', defaultWidth: 150, sortValue: line => userText(line.created_by), filterValue: line => userText(line.created_by), exportValue: line => userText(line.created_by), render: line => userDisplay(line.created_by) },
    { key: 'created_date', header: 'Created Date', group: 'audit', defaultWidth: 150, sortValue: line => line.created_at, filterValue: line => formatDateTime(line.created_at), exportValue: line => line.created_at, render: line => formatDateTime(line.created_at) },
    { key: 'uuid', header: 'UUID', group: 'system', defaultWidth: 160, sortValue: line => line.id, filterValue: line => line.id, exportValue: line => line.id, render: line => <span className="font-mono">{line.id.slice(0, 8)}…</span> },
    { key: 'status', header: 'Status', group: 'audit', defaultWidth: 100, sortValue: () => si.status, filterValue: () => si.status, exportValue: () => si.status, render: () => <StatusBadge status={statusToShared[si.status]} label={si.status} /> },
  ]
  const lineProfiles: LineColumnProfile[] = [
    { key: 'default', label: 'Default', columnKeys: ['no', 'item_code', 'item_desc', 'desc', 'qty', 'uom', 'warehouse', 'price', 'disc_pct', 'vat_code', 'vat_pct', 'net', 'vat_amt', 'total'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'accounting', label: 'Accounting', columnKeys: ['no', 'item_code', 'desc', 'acct', 'branch', 'department', 'cost_center', 'vat_code', 'vat_amt', 'ewt_code', 'ewt_amt', 'inventory_cost', 'net', 'total'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'tax', label: 'Tax', columnKeys: ['no', 'item_code', 'desc', 'vat_code', 'atc', 'tax_base', 'vat_pct', 'vat_amt', 'ewt_code', 'ewt_amt', 'tax_class'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'audit', label: 'Audit', columnKeys: ['no', 'item_code', 'desc', 'source_doc', 'journal_entry', 'posting_rule', 'inventory_tx', 'created_by', 'created_date', 'uuid', 'status', 'acct', 'branch'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'sales', label: 'Sales', columnKeys: ['no', 'item_code', 'item_desc', 'desc', 'qty', 'uom', 'price', 'disc_pct', 'disc_amt', 'net', 'total'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
  ]
  const selectedLine = lines.find(line => line.id === selectedLineId) ?? null
  const lineDetailSections: DetailSection[] = selectedLine ? [
    { key: 'tax', title: 'Tax Breakdown', fields: [
      { label: 'VAT Code', value: selectedLine.vat_code_id ? vatCodes[selectedLine.vat_code_id]?.code ?? '—' : '—' },
      { label: 'VAT Base', value: <AmountCell amount={num(selectedLine.net_amount)} /> },
      { label: 'VAT Rate', value: `${num(selectedLine.vat_code_id ? vatCodes[selectedLine.vat_code_id]?.rate : 0)}%` },
      { label: 'VAT Amount', value: <AmountCell amount={num(selectedLine.vat_amount)} /> },
    ] },
    { key: 'dimensions', title: 'Operational Dimensions', fields: [
      { label: 'Branch', value: branchName || 'Not assigned' },
      { label: 'Warehouse', value: warehouseLabel(selectedLine.warehouse_id) || 'Not assigned' },
      { label: 'Department', value: departmentLabel(selectedLine.department_id || si.department_id) || 'Not assigned' },
      { label: 'Cost Center', value: costCenterLabel(selectedLine.cost_center_id || si.cost_center_id) || 'Not assigned' },
      { label: 'Salesperson', value: employeeLabel(selectedLine.salesperson_id || si.salesperson_id) || 'Not assigned' },
    ] },
    { key: 'inventory', title: 'Inventory and COGS', fields: [
      { label: 'Inventory Account', value: accountLabel(selectedLine.inventory_account_id) },
      { label: 'COGS Account', value: accountLabel(selectedLine.cogs_account_id) },
      { label: 'Unit Cost', value: selectedLine.unit_cost != null ? <AmountCell amount={num(selectedLine.unit_cost)} /> : 'Not posted' },
      { label: 'Inventory Cost', value: selectedLine.inventory_cost != null ? <AmountCell amount={num(selectedLine.inventory_cost)} /> : 'Not posted' },
      { label: 'Inventory Transaction', value: selectedLine.inventory_transaction_id ? <span className="font-mono">{selectedLine.inventory_transaction_id}</span> : 'Not posted' },
    ] },
    { key: 'audit', title: 'Audit Information', fields: [
      { label: 'Created', value: formatDateTime(selectedLine.created_at) },
      { label: 'Last Modified', value: formatDateTime(selectedLine.updated_at) },
      { label: 'Created By', value: userDisplay(selectedLine.created_by) },
    ] },
    ...(si.reference ? [{ key: 'source', title: 'Source References', fields: [{ label: 'External Reference', value: si.reference }] }] : []),
    { key: 'rule', title: 'Posting Rule Used', fields: [
      { label: 'Account Source', value: selectedLine.revenue_account_id ? 'Item / document line account' : 'Unmapped' },
      { label: 'Account', value: accountLabel(selectedLine.revenue_account_id) },
    ] },
    ...(selectedLine.item_id && items[selectedLine.item_id]?.notes
      ? [{ key: 'notes', title: 'Item Notes', fields: [{ label: 'Notes', value: items[selectedLine.item_id].notes }] }]
      : []),
  ] : []
  const linesTab = erpTabSection(
    'Lines',
    'Transaction line items, tax codes, and source-backed posting accounts.',
    <>
      <LineGrid columns={lineColumns} rows={lines} getRowKey={line => line.id} emptyLabel="No lines on this invoice."
        profiles={lineProfiles} initialProfileKey="default"
        storageKey={`company:${companyId || 'none'}:sales-invoice:lines`}
        tableLabel="Sales Invoice Lines"
        onRefresh={load}
        onRowClick={line => setSelectedLineId(previous => previous === line.id ? null : line.id)} selectedKey={selectedLineId ?? undefined}
        renderExpandedRow={() => selectedLine
          ? <LineDetailPanel title={`Line ${selectedLine.line_number} — ${selectedLine.description}`} sections={lineDetailSections} onClose={() => setSelectedLineId(null)} />
          : null}
        summary={[
          { key: 'lines', label: 'Lines', value: lines.length },
          { key: 'qty', label: 'Quantity', value: lines.reduce((sum, line) => sum + num(line.quantity), 0) },
          { key: 'net', label: 'Net Sales', value: <AmountCell amount={netOfVat} /> },
          { key: 'vat', label: 'VAT', value: <AmountCell amount={num(si.total_vat_amount)} /> },
          { key: 'ewt', label: 'EWT', value: <AmountCell amount={cwt} /> },
          { key: 'gross', label: 'Gross', value: <AmountCell amount={subtotal} /> },
          { key: 'discount', label: 'Discount', value: <AmountCell amount={discounts} /> },
          { key: 'grand', label: 'Grand Total', value: <AmountCell amount={num(si.total_amount)} />, emphasis: true },
        ]} />
      <p className="text-[10px] text-gray-400 mt-1.5">Click any row to inspect available tax, audit, source, posting rule, and item-note details.</p>
    </>,
  )

  // ── Financial Summary (full, §14) ───────────────────────────
  const financialGroups: Array<{ title: string; rows: Array<{ key: string; component: string; basis: ReactNode; amount: ReactNode; strong?: boolean }> }> = [
    {
      title: 'Commercial Summary',
      rows: [
        { key: 'gross-line', component: 'Gross Line Amount', basis: 'Net sales plus line discounts before invoice total computation.', amount: <AmountCell amount={subtotal} /> },
        { key: 'discounts', component: 'Line Discounts', basis: 'Discounts captured on invoice lines.', amount: discounts > 0 ? <span>(<AmountCell amount={discounts} />)</span> : <AmountCell amount={0} /> },
        { key: 'net-sales', component: 'Net Sales', basis: 'VATable, zero-rated, and exempt sales before output VAT.', amount: <AmountCell amount={netOfVat} />, strong: true },
        { key: 'vatable', component: 'VATable Sales', basis: 'Taxable sales base.', amount: <AmountCell amount={num(si.total_taxable_amount)} /> },
        { key: 'zero', component: 'Zero-Rated Sales', basis: 'Zero-rated sales base.', amount: <AmountCell amount={num(si.total_zero_rated_amount)} /> },
        { key: 'exempt', component: 'VAT-Exempt Sales', basis: 'VAT-exempt sales base.', amount: <AmountCell amount={num(si.total_exempt_amount)} /> },
        { key: 'output-vat', component: 'Output VAT', basis: 'See Tax Impact tab for ledger and filing context.', amount: <AmountCell amount={num(si.total_vat_amount)} /> },
        { key: 'invoice-total', component: 'Invoice Total', basis: 'Gross customer receivable before receipt applications.', amount: <AmountCell amount={num(si.total_amount)} />, strong: true },
        { key: 'expected-cwt', component: 'Expected CWT', basis: 'Informational withholding estimate until receipt, application, or certificate workflow recognizes actual CWT.', amount: cwt > 0 ? <span>(<AmountCell amount={cwt} />)</span> : <AmountCell amount={0} /> },
        { key: 'expected-net', component: 'Expected Net Collectible', basis: 'Invoice Total less Expected CWT; does not reduce invoice revenue.', amount: <AmountCell amount={num(si.total_amount) - cwt} />, strong: true },
        { key: 'collected', component: 'Amount Collected', basis: `${collection.receiptCount} posted receipt application${collection.receiptCount !== 1 ? 's' : ''}.`, amount: <AmountCell amount={collection.paid + collection.cwt} /> },
        { key: 'payment-applications', component: 'Payment Applications', basis: 'Posted receipts applied to this invoice.', amount: <AmountCell amount={collection.paid} /> },
        { key: 'actual-cwt', component: 'Actual CWT Recognized', basis: 'Recognized only from posted receipt/application evidence.', amount: <AmountCell amount={collection.cwt} /> },
        { key: 'balance-due', component: 'Balance Due', basis: <button type="button" onClick={() => navigate(`/ar-aging?tab=ledger&customerId=${si.customer_id}`)} className="text-blue-700 hover:underline">Open customer ledger</button>, amount: <AmountCell amount={collection.balance} />, strong: true },
      ],
    },
    ...(inventoryItemCount > 0 ? [{
      title: 'Inventory and Cost Summary',
      rows: [
        { key: 'inventory-count', component: 'Inventory Items Count', basis: 'Inventory-impacting invoice lines.', amount: <span>{inventoryItemCount}</span> },
        { key: 'quantity-issued', component: 'Quantity Issued', basis: 'Quantity released from inventory-impacting lines.', amount: <span>{quantityIssued}</span> },
        { key: 'inventory-cost', component: 'Inventory Cost', basis: inventoryCost > 0 ? 'Authoritative inventory cost consumed by posted Sales Invoice inventory lines.' : 'No inventory cost posted for this invoice.', amount: <AmountCell amount={inventoryCost} /> },
        { key: 'cogs', component: 'Cost of Goods Sold', basis: 'COGS from posted Sales Invoice inventory/cost impact.', amount: <AmountCell amount={inventoryCost} /> },
        { key: 'inventory-reduction', component: 'Inventory Reduction', basis: 'Inventory asset reduction from posted Sales Invoice inventory/cost impact.', amount: <AmountCell amount={inventoryCost} /> },
        { key: 'cost-adjustment', component: 'Cost Adjustment', basis: 'No separate cost adjustment recorded on this invoice.', amount: <AmountCell amount={0} /> },
        { key: 'inventory-variance', component: 'Inventory Variance', basis: 'No inventory variance recorded on this invoice.', amount: <AmountCell amount={0} /> },
        { key: 'gross-profit', component: 'Gross Profit', basis: 'Net Sales less authoritative Sales Invoice COGS.', amount: <AmountCell amount={grossProfit} /> },
        { key: 'gross-margin', component: 'Gross Margin %', basis: 'Gross Profit divided by Net Sales.', amount: <span>{grossMargin == null ? 'Not Applicable' : `${grossMargin.toFixed(2)}%`}</span> },
      ],
    }] : []),
    {
      title: 'Accounting Reconciliation',
      rows: [
        { key: 'commercial-debit', component: 'Commercial GL Debits', basis: 'Commercial / Revenue Accounting Impact section debit total.', amount: <AmountCell amount={commercialGlDebit} /> },
        { key: 'commercial-credit', component: 'Commercial GL Credits', basis: 'Commercial / Revenue Accounting Impact section credit total.', amount: <AmountCell amount={commercialGlCredit} /> },
        { key: 'inventory-debit', component: 'Inventory GL Debits', basis: 'Inventory / Cost Accounting Impact section debit total.', amount: <AmountCell amount={inventoryGlDebit} /> },
        { key: 'inventory-credit', component: 'Inventory GL Credits', basis: 'Inventory / Cost Accounting Impact section credit total.', amount: <AmountCell amount={inventoryGlCredit} /> },
        { key: 'combined-debit', component: 'Combined Debits', basis: 'Combined commercial and inventory debit total.', amount: <AmountCell amount={combinedGlDebit} />, strong: true },
        { key: 'combined-credit', component: 'Combined Credits', basis: 'Combined commercial and inventory credit total.', amount: <AmountCell amount={combinedGlCredit} />, strong: true },
        { key: 'difference', component: 'Difference', basis: 'Combined debits less combined credits.', amount: <AmountCell amount={combinedGlDifference} /> },
        { key: 'balanced', component: 'Balanced Status', basis: 'Authoritative preview or posted journal balance.', amount: <span>{Math.abs(combinedGlDifference) <= 0.01 ? 'Balanced' : 'Unbalanced'}</span>, strong: true },
      ],
    },
  ]
  const financialTab = erpTabSection(
    'Financial',
    'Full computation and collection interpretation for this invoice.',
    <div className="space-y-3">
      {financialGroups.map(group => (
        <div key={group.title} className="overflow-x-auto rounded border border-gray-200">
          <div className="border-b border-gray-200 bg-gray-50 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-gray-700">{group.title}</div>
          <table className={ERP_TABLE}>
            <thead className={ERP_THEAD}>
              <tr>
                {['Financial Component', 'Basis or Explanation', 'Amount'].map((label, i) => (
                  <th key={label} className={`${ERP_TH} ${i === 2 ? 'text-right' : 'text-left'}`}>{label}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {group.rows.map(row => (
                <tr key={row.key}>
                  <td className={`${ERP_TD} ${row.strong ? 'font-semibold text-gray-900' : 'text-gray-800'}`}>{row.component}</td>
                  <td className={`${ERP_TD} text-gray-500`}>{row.basis}</td>
                  <td className={`${ERP_TD_NUM} ${row.strong ? 'font-semibold text-gray-900' : ''}`}>{row.amount}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
      {cwt > 0 && (
        <p className="rounded border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-500">
          Expected CWT is informational until receipt, payment application, or certificate recognition.
        </p>
      )}
    </div>,
  )

  const glTab = <GLImpactPanel companyId={companyId} sourceDocType="SI" sourceDocId={si.id} previewRows={[]} separatedSalesInvoiceImpact withholdingInfo={withholdingInfo} />
  const taxTab = <TaxImpactPanel sourceDocType="SI" sourceDocId={si.id} fallbackLabel="Output VAT"
    fallbackBase={num(si.total_taxable_amount)} fallbackRate={12} fallbackAmount={num(si.total_vat_amount)}
    expectedCwt={cwt} actualCwt={collection.cwt}
    customerTin={si.customer_tin_snapshot ? normalizePhTin(si.customer_tin_snapshot) : customer ? composePhTin(customer.tin, customer.tin_branch_code) : null}
    customerBranch={getPhTinBranch(si.customer_tin_snapshot || customer?.tin || '', customer?.tin_branch_code)}
    documentNumber={si.si_number}
    documentDate={si.date}
    branchName={branchName}
    vatClassification={customer ? (TAX_TYPE_LABEL[customer.default_tax_type] ?? customer.default_tax_type) : null} />

  // ── Posting Validation ──────────────────────────────────────
  const postable = si.status === 'draft' || si.status === 'approved'
  const readinessState = (pattern: RegExp): ValidationCheck['state'] =>
    readiness.loading ? 'pending' : readiness.blockers.some(blocker => pattern.test(blocker)) ? 'blocked' : 'ok'
  const arithmeticBalanced = Math.abs(netOfVat + num(si.total_vat_amount) - num(si.total_amount)) <= 0.01
  const inventoryLineCount = lines.filter(line => line.warehouse_id || line.inventory_transaction_id || num(line.inventory_cost) > 0).length
  const inventoryEvidenceComplete = inventoryLineCount === 0 || lines
    .filter(line => line.warehouse_id || line.inventory_account_id || line.cogs_account_id)
    .every(line => line.warehouse_id && line.inventory_account_id && line.cogs_account_id && (si.status !== 'posted' || line.inventory_transaction_id || num(line.inventory_cost) === 0))
  const docChecks: ValidationCheck[] = [
    { key: 'balanced', label: 'Balanced', state: arithmeticBalanced ? 'ok' : 'blocked', detail: 'Net sales plus VAT agrees to the invoice total.' },
    { key: 'period', label: 'Period Open', state: readinessState(/period|fiscal/i) },
    { key: 'branch', label: 'Branch Active', state: branchName ? readinessState(/branch/i) : 'blocked' },
    { key: 'dimensions', label: 'Operational Dimension Capture', state: assignedContextFields.length > 0 || lines.some(line => line.department_id || line.cost_center_id || line.warehouse_id || line.salesperson_id) ? 'ok' : 'info', detail: assignedContextFields.length > 0 ? 'Source-backed Sales Context dimensions are stored on this invoice.' : 'No operational dimensions assigned.' },
    { key: 'series', label: 'Series Valid', state: si.si_number && seriesName ? readinessState(/series|number/i) : 'blocked' },
    { key: 'tax', label: 'Tax Valid', state: lines.every(line => line.vat_code_id || num(line.vat_amount) === 0) ? 'ok' : 'blocked' },
    { key: 'inventory', label: 'Inventory Posted', state: inventoryEvidenceComplete ? 'ok' : 'blocked', detail: inventoryLineCount > 0 ? 'Inventory lines carry warehouse, accounts, and posting evidence.' : 'No inventory impact on this invoice.' },
    { key: 'cost', label: 'Cost Posted', state: inventoryEvidenceComplete ? 'ok' : 'blocked', detail: inventoryCost > 0 ? 'COGS and inventory cost are available from posted line evidence.' : 'No COGS was posted for this invoice.' },
    { key: 'approval', label: 'Approval Passed', state: si.status === 'draft' ? 'pending' : si.status === 'approved' || si.status === 'posted' ? 'ok' : 'info' },
    { key: 'engine', label: 'Posting Engine Version', state: 'info', detail: 'The runtime version is not exposed by the current posting process.' },
    { key: 'hash', label: 'Document Hash', state: 'info', detail: 'A persisted document hash is not available in the current schema.' },
    { key: 'lines', label: 'At least one line item', state: lines.length > 0 ? 'ok' : 'blocked' },
    { key: 'cust', label: 'Customer active with tax profile', state: customer?.is_active ? 'ok' : customer ? 'blocked' : 'info' },
  ]
  if (si.status === 'posted') {
    docChecks.push({ key: 'posted', label: 'Posted to the general ledger', state: 'ok' })
    docChecks.push({ key: 'frozen', label: 'Frozen by lifecycle controls — correct via void/reverse only', state: 'ok' })
  } else if (si.status === 'cancelled') {
    docChecks.push({ key: 'void', label: 'Voided — SI number retired per BIR (never reused)', state: 'info' })
  }
  const validationChecks = postable ? [...readinessToChecks(readiness), ...docChecks] : docChecks
  const validationTab = (
    <PostingValidationPanel checks={validationChecks}
      title={si.status === 'posted' ? 'Posted Successfully · Frozen by Lifecycle Controls' : 'Posting Validation'}
      footnote={postable
        ? 'Postable invoices show setup, arithmetic, tax, approval, and posting-readiness checks.'
        : 'Saved document checks reflect the current lifecycle state.'} />
  )

  // ── Workflow tab ────────────────────────────────────────────
  const nextPermittedAction = si.status === 'draft'
    ? 'Submit'
    : si.status === 'approved'
      ? 'Post'
      : si.status === 'posted' && collection.balance > 0.005
        ? 'Create Receipt'
        : 'No direct action'
  const workflowRows = [
    { stage: 'Draft', status: si.created_at ? 'Completed' : 'Pending', date: si.created_at, actor: si.created_by, role: 'Creator', remarks: 'Invoice created' },
    { stage: 'Approved', status: si.approved_at ? 'Completed' : si.status === 'draft' ? 'Pending' : 'Not recorded', date: si.approved_at, actor: si.approved_by, role: 'Approver', remarks: si.approved_at ? 'Approval recorded' : 'Awaiting approval when routed' },
    { stage: 'Posted', status: si.posted_at ? 'Completed' : si.status === 'cancelled' ? 'Voided' : 'Pending', date: si.posted_at, actor: si.posted_by, role: 'Poster', remarks: si.posted_at ? 'Posted to accounting' : 'Not posted' },
    { stage: 'Collection', status: collection.status || 'Not posted', date: null, actor: null, role: 'AR / Cashier', remarks: nextPermittedAction },
    { stage: 'Lock', status: lockLabel, date: si.updated_at, actor: si.updated_by, role: 'System', remarks: si.status === 'draft' ? 'Editable document' : 'Read-only lifecycle state' },
  ]
  const workflowTab = erpTabSection(
    'Workflow',
    'Lifecycle status for this transaction.',
    <div className="space-y-2">
      <section className="border border-gray-200 rounded p-3">
        <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500 mb-2">Lifecycle</div>
        <WorkflowStrip steps={workflow.steps} currentKey={workflow.currentKey} />
      </section>
      <div className="overflow-x-auto border border-gray-200 rounded">
        <table className={ERP_TABLE}>
          <thead className={ERP_THEAD}>
            <tr>
              {['Stage', 'Status', 'Responsible User', 'Role', 'Date and Time', 'Next Action / Remarks'].map(label => (
                <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {workflowRows.map(row => (
              <tr key={row.stage}>
                <td className={`${ERP_TD} text-gray-800`}>{row.stage}</td>
                <td className={`${ERP_TD} text-gray-600`}>{row.status}</td>
                <td className={`${ERP_TD} text-gray-500 truncate`}>{userDisplay(row.actor)}</td>
                <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.role}</td>
                <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.date ? formatDateTime(row.date) : '—'}</td>
                <td className={`${ERP_TD} text-gray-500`}>{row.remarks}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>,
  )

  // ── Approval tab ────────────────────────────────────────────
  const approvalTab = erpTabSection(
    'Approval',
    'Approval routing and electronic authorization history.',
    approvals.length > 0 ? (
    <div className="overflow-x-auto border border-gray-200 rounded">
      <table className={ERP_TABLE}>
        <thead className={ERP_THEAD}>
          <tr>
            {['Approval Level', 'Approver', 'Role', 'Status', 'Date and Time', 'Comments / Rejection Reason', 'Electronic Signature'].map(label => (
              <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {approvals.map(row => (
            <tr key={row.id}>
              <td className={ERP_TD}>{row.step_sequence}</td>
              <td className={`${ERP_TD} text-gray-600`}>{row.actual_approver_id || row.required_approver_id ? userDisplay(row.actual_approver_id || row.required_approver_id) : 'Pending approver'}</td>
              <td className={`${ERP_TD} text-gray-600`}>{row.required_approver_type}</td>
              <td className={ERP_TD}><StatusBadge status={row.status === 'approved' ? 'approved' : row.status === 'rejected' ? 'error' : 'pending'} label={row.status} /></td>
              <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{formatDateTime(row.acted_at || row.submitted_at)}</td>
              <td className={`${ERP_TD} text-gray-600`}>{row.remarks || (row.status === 'pending' ? 'Awaiting approval' : '—')}</td>
              <td className={`${ERP_TD} text-gray-400`}>Not recorded</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  ) : (
    <CompactEmptyState>
      No approval workflow configured for this Sales Invoice.
    </CompactEmptyState>
  ),
  )

  // ── Audit Trail ─────────────────────────────────────────────
  const auditFacts = [
    { event: 'Created', user: si.created_by, at: si.created_at, status: 'Recorded' },
    { event: 'Last Updated', user: si.updated_by, at: si.updated_at, status: 'Recorded' },
    { event: 'Submitted / Approved', user: si.approved_by, at: si.approved_at, status: si.approved_at ? 'Recorded' : 'Not recorded' },
    { event: 'Posted', user: si.posted_by, at: si.posted_at, status: si.posted_at ? 'Recorded' : 'Not posted' },
    ...(si.status === 'cancelled' ? [{ event: 'Voided / Cancelled', user: si.updated_by, at: si.updated_at, status: 'Voided' }] : []),
    { event: 'Lock State', user: null, at: si.updated_at, status: lockLabel },
  ]
  const auditTab = erpTabSection(
    'Audit',
    'Chronological document facts and system audit trail.',
    <div className="space-y-2">
      <div className="overflow-x-auto border border-gray-200 rounded">
        <table className={ERP_TABLE}>
          <thead className={ERP_THEAD}>
            <tr>
              {['Event', 'User', 'Date and Time', 'Status'].map(label => (
                <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {auditFacts.map(row => (
              <tr key={row.event}>
                <td className={`${ERP_TD} text-gray-800`}>{row.event}</td>
                <td className={`${ERP_TD} text-gray-600`}>{userDisplay(row.user)}</td>
                <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.at ? formatDateTime(row.at) : '—'}</td>
                <td className={`${ERP_TD} text-gray-500`}>{row.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <AuditTrailSection tableName="sales_invoices" recordId={si.id} initiallyExpanded hideRawUserIds />
    </div>,
  )

  // ── Activity Timeline (lifecycle facts; transaction_events UI wiring remains PXL-AUD-050) ──
  const timelineEvents = [
    { label: 'Created', at: si.created_at },
    ...(si.approved_at ? [{ label: 'Approved', at: si.approved_at }] : []),
    ...(si.posted_at ? [{ label: 'Posted', at: si.posted_at }] : []),
    ...(collection.receiptCount > 0 ? [{ label: `Collection applied (${collection.receiptCount} receipt${collection.receiptCount !== 1 ? 's' : ''})`, at: null }] : []),
    ...(si.status === 'cancelled' ? [{ label: 'Voided', at: si.updated_at }] : []),
  ]
  const timelineTab = erpTabSection(
    'Activity',
    'Transaction activity and system events.',
    <ol className="relative border-l border-gray-200 ml-2 space-y-3">
      {timelineEvents.map((e, i) => (
        <li key={i} className="ml-4">
          <span className="absolute -left-1 w-2 h-2 rounded-full bg-gray-300 border border-white" />
          <div className="text-xs text-gray-800">{e.label}</div>
          <div className="text-xs text-gray-400">{e.at ? formatDateTime(e.at) : '—'}</div>
        </li>
      ))}
      <li className="ml-4 text-[11px] text-gray-400">No additional operational activity events recorded.</li>
    </ol>,
  )

  // ── Notes ───────────────────────────────────────────────────
  const notesTab = erpTabSection(
    'Notes',
    'Internal, customer, accounting, and collection notes.',
    <div className="overflow-x-auto border border-gray-200 rounded">
      <table className={ERP_TABLE}>
        <thead className={ERP_THEAD}>
          <tr>
            {['Date and Time', 'User', 'Category', 'Visibility', 'Note', 'Action'].map(label => (
              <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {si.memo ? (
            <tr>
              <td className={ERP_TD}>{formatDateTime(si.created_at)}</td>
              <td className={`${ERP_TD} text-gray-500`}>{si.created_by ? userDisplay(si.created_by) : 'System'}</td>
              <td className={ERP_TD}>Customer-Facing</td>
              <td className={ERP_TD}>Print / email memo</td>
              <td className={`${ERP_TD} whitespace-pre-wrap text-gray-700`}>{si.memo}</td>
              <td className={`${ERP_TD} text-gray-400`}>Read only</td>
            </tr>
          ) : (
            <tr><td colSpan={6} className={ERP_EMPTY_CELL}>No notes recorded.</td></tr>
          )}
        </tbody>
      </table>
    </div>,
  )

  // ── Attachments (no storage integration yet) ────────────────
  const attachmentsTab = erpTabSection(
    'Attachments',
    'Files linked to this transaction.',
    <>
    <div className="overflow-x-auto border border-gray-200 rounded">
      <table className={ERP_TABLE}>
        <thead className={ERP_THEAD}><tr>
          {['File Name', 'Document Type', 'Description', 'Uploaded By', 'Upload Date', 'File Size', 'OCR Status', 'Preview', 'Download'].map(label => (
            <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
          ))}
        </tr></thead>
        <tbody><tr><td colSpan={9} className={ERP_EMPTY_CELL}>No attachments are linked to this invoice.</td></tr></tbody>
      </table>
    </div>
    <p className="text-[10px] text-gray-400">Sales Invoice attachment storage and OCR are not configured; the CAS attachment register remains the system-of-record register.</p>
    </>,
  )

  // ── Related Party — embedded customer profile, not permanent header content ──
  const relatedPartyField = (label: string, value: ReactNode, wide = false) => (
    <div className={wide ? 'sm:col-span-2' : ''} key={label}>
      <div className="text-[10px] uppercase tracking-wide text-gray-400 mb-0.5">{label}</div>
      <div className="text-xs text-gray-700 break-words">{value ?? '—'}</div>
    </div>
  )
  const relatedPartySection = (title: string, fields: ReactNode, className = '', defaultOpen = true) => (
    <details open={defaultOpen} className={`border border-gray-200 rounded min-w-0 ${className}`}>
      <summary className="cursor-pointer px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 hover:bg-gray-50">{title}</summary>
      <div className="border-t border-gray-100 p-3">
        {fields}
      </div>
    </details>
  )
  const relatedPartyGrid = (fields: Array<[string, ReactNode, boolean?]>) => (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2">
      {fields.map(([label, value, wide]) => relatedPartyField(label, value, wide))}
    </div>
  )
  const customerTaxLabel = customer ? (TAX_TYPE_LABEL[customer.default_tax_type] ?? customer.default_tax_type) : '—'
  const customerSince = customer?.created_at ? new Date(customer.created_at).toLocaleDateString('en-PH') : '—'
  const mutedValue = (value: string) => <span className="text-gray-400">{value}</span>
  const customerStatusBadge = customer
    ? <StatusBadge status={customer.is_active ? 'active' : 'inactive'} label={customer.is_active ? 'Active' : 'Inactive'} />
    : '—'
  const creditLimitValue = customer?.credit_limit != null ? <AmountCell amount={num(customer.credit_limit)} /> : '—'
  const outstandingValue = customerOutstanding != null ? <AmountCell amount={customerOutstanding} /> : '—'
  const availableCreditValue = availableCredit != null ? <AmountCell amount={availableCredit} /> : '—'
  const lastPaymentValue = lastPayment
    ? <span><DateCell date={lastPayment.date} /> · <AmountCell amount={lastPayment.amount} /></span>
    : '—'
  const agingBuckets = agingBalances.reduce((acc, row) => {
    const amount = num(row.balance_due)
    const days = num(row.days_overdue)
    if (days <= 0) acc.current += amount
    else if (days <= 30) acc.days_1_30 += amount
    else if (days <= 60) acc.days_31_60 += amount
    else if (days <= 90) acc.days_61_90 += amount
    else acc.over_90 += amount
    acc.total += amount
    return acc
  }, { current: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 0 })
  const relatedPartyTab = erpTabSection(
    'Related Party',
    'Embedded customer profile for this transaction.',
    !customer ? (
    <CompactEmptyState>
      Customer master record unavailable. The invoice keeps the saved customer snapshot.
    </CompactEmptyState>
  ) : (
    <div className="space-y-3">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
        {relatedPartySection('Identity', relatedPartyGrid([
          ['Customer', customerLink, true],
          ['Customer Code', customer.customer_code],
          ['Status', customerStatusBadge],
          ['Registered Name', customer.registered_name, true],
          ['Trade Name', customer.trade_name || '—'],
          ['Business Style', customer.business_style || '—'],
          ['Customer Group', customer.customer_group || '—'],
          ['Customer Since', customerSince],
        ]))}
        {relatedPartySection('Tax Profile', relatedPartyGrid([
          ['TIN', si.customer_tin_snapshot ? normalizePhTin(si.customer_tin_snapshot) : composePhTin(customer.tin, customer.tin_branch_code)],
          ['TIN Branch', getPhTinBranch(si.customer_tin_snapshot || customer.tin, customer.tin_branch_code)],
          ['VAT Classification', customerTaxLabel],
          ['Withholding Status', customer.is_subject_to_cwt ? 'Subject to CWT' : 'Not subject to CWT'],
        ]))}
        {relatedPartySection('Credit Profile', relatedPartyGrid([
          ['Credit Limit', creditLimitValue],
          ['Outstanding AR', outstandingValue],
          ['Available Credit', availableCreditValue],
          ['Last Payment', lastPaymentValue],
        ]))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
        {relatedPartySection('Contacts', relatedPartyGrid([
          ['Contact', customer.contact_person || '—'],
          ['Email', customer.email || '—'],
          ['Phone', customer.phone_number || '—'],
        ]), '', false)}
        {relatedPartySection('Addresses', relatedPartyGrid([
          ['Registered Address', customer.registered_address || '—', true],
          ['Delivery Address', customer.delivery_address || '—', true],
        ]), '', false)}
        {relatedPartySection('Payment Information', relatedPartyGrid([
          ['Default Terms', termLabel(customer.default_terms_id || si.payment_terms_id)],
          ['Payment Method', mutedValue('Selected at receipt')],
          ['Price List', mutedValue('Not assigned')],
          ['Delivery Terms', mutedValue('Not assigned')],
        ]), '', false)}
        {relatedPartySection('Sales Information', relatedPartyGrid([
          ['Sales Territory', mutedValue('Not assigned')],
          ['Industry', mutedValue('Not assigned')],
          ['Price Level', mutedValue('Not assigned')],
          ['Customer Group', customer.customer_group || '—'],
        ]), '', false)}
      </div>

      {relatedPartySection('Aging Summary', (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
          {[
            ['Current', agingBuckets.current],
            ['1-30 Days', agingBuckets.days_1_30],
            ['31-60 Days', agingBuckets.days_31_60],
            ['61-90 Days', agingBuckets.days_61_90],
            ['Over 90', agingBuckets.over_90],
            ['Total AR', agingBuckets.total],
          ].map(([label, amount]) => (
            <div key={String(label)} className="bg-gray-50 border border-gray-100 rounded px-2.5 py-1.5">
              <div className="text-[10px] uppercase tracking-wide text-gray-400">{label}</div>
              <div className="text-xs font-semibold text-gray-800"><AmountCell amount={num(amount)} /></div>
            </div>
          ))}
        </div>
      ))}

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-3">
        {relatedPartySection('Recent Invoices', (
          <div className="overflow-x-auto border border-gray-200 rounded">
            <table className={ERP_TABLE}>
              <thead className={ERP_THEAD}><tr>
                {['Date', 'Invoice', 'Due Date', 'Status', 'Amount'].map(label => (
                  <th key={label} className={`${ERP_TH} ${label === 'Amount' ? 'text-right' : 'text-left'}`}>{label}</th>
                ))}
              </tr></thead>
              <tbody className="divide-y divide-gray-100">
                {recentInvoices.length === 0 ? (
                  <tr><td colSpan={5} className={ERP_EMPTY_CELL}>No recent invoices found.</td></tr>
                ) : recentInvoices.map(row => (
                  <tr key={row.id} className="hover:bg-gray-50">
                    <td className={ERP_TD}><DateCell date={row.date} /></td>
                    <td className={ERP_TD}>
                      <button onClick={() => navigate(`/sales-invoices/${row.id}`)} className="font-mono text-blue-700 hover:underline">{row.si_number}</button>
                    </td>
                    <td className={ERP_TD}><DateCell date={row.due_date} /></td>
                    <td className={ERP_TD}><StatusBadge status={statusToShared[row.status as SIStatus] ?? row.status} label={row.status} /></td>
                    <td className={ERP_TD_NUM}><AmountCell amount={num(row.total_amount)} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ), '', false)}
        {relatedPartySection('Recent Payments', (
          <div className="overflow-x-auto border border-gray-200 rounded">
            <table className={ERP_TABLE}>
              <thead className={ERP_THEAD}><tr>
                {['Date', 'Receipt', 'Status', 'Amount', 'CWT'].map(label => (
                  <th key={label} className={`${ERP_TH} ${['Amount', 'CWT'].includes(label) ? 'text-right' : 'text-left'}`}>{label}</th>
                ))}
              </tr></thead>
              <tbody className="divide-y divide-gray-100">
                {recentPayments.length === 0 ? (
                  <tr><td colSpan={5} className={ERP_EMPTY_CELL}>No recent payments found.</td></tr>
                ) : recentPayments.map(row => (
                  <tr key={row.id} className="hover:bg-gray-50">
                    <td className={ERP_TD}><DateCell date={row.receipt_date} /></td>
                    <td className={ERP_TD}>
                      <button onClick={() => navigate('/receipts')} className="font-mono text-blue-700 hover:underline">{row.receipt_number}</button>
                    </td>
                    <td className={ERP_TD}><StatusBadge status="posted" label={row.status} /></td>
                    <td className={ERP_TD_NUM}><AmountCell amount={num(row.total_amount)} /></td>
                    <td className={ERP_TD_NUM}><AmountCell amount={num(row.total_cwt)} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ), '', false)}
      </div>
    </div>
  ),
  )

  // ── System ──────────────────────────────────────────────────
  const systemTab = erpTabSection(
    'System',
    'Technical identifiers and engine metadata for support and audit review.',
    <div className="overflow-x-auto border border-gray-200 rounded">
      <table className={ERP_TABLE}>
        <thead className={ERP_THEAD}>
          <tr>
            {['System Field', 'Value', 'Purpose'].map(label => (
              <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {[
            ['Document UUID', si.id, 'Support and audit trace'],
            ['Company ID', si.company_id, 'Tenant trace'],
            ['Branch ID', si.branch_id, 'Branch trace'],
            ['Customer ID', si.customer_id, 'Related party trace'],
            ['Fiscal Period ID', si.fiscal_period_id || 'Not assigned', 'Fiscal calendar trace'],
            ['Journal Reference', si.journal_entry_id || 'Not posted', 'General ledger linkage'],
            ['Source Module', 'Sales', 'Document lineage'],
            ['Source Type', 'SI', 'Document lineage'],
            ['Number Series', seriesName || 'Not configured', 'Numbering trace'],
            ['Posting Process', 'Sales Invoice Posting', 'Authoritative lifecycle process'],
            ['Void Process', 'Sales Invoice Void', 'Authoritative lifecycle process'],
            ['Posting Engine Version', 'Not exposed', 'Support metadata unavailable'],
            ['Tax Engine Version', 'Not exposed', 'Support metadata unavailable'],
            ['Document Hash', 'Not available', 'Integrity metadata unavailable'],
            ['Tax Ledger Source', 'Tax Detail Entries', 'Tax lineage'],
            ['Lock State', lockLabel, 'Lifecycle control'],
            ['Created Timestamp', si.created_at, 'Record history'],
            ['Updated Timestamp', si.updated_at, 'Record history'],
          ].map(([field, value, purpose]) => (
            <tr key={field}>
              <td className={`${ERP_TD} text-gray-600`}>{field}</td>
              <td className={`${ERP_TD} font-mono text-gray-700`} title={String(value)}>{value}</td>
              <td className={`${ERP_TD} text-gray-500`}>{purpose}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>,
  )

  const tabContent = {
    lines: linesTab,
    financial: financialTab,
    gl: glTab,
    tax: taxTab,
    validation: validationTab,
    workflow: workflowTab,
    approval: approvalTab,
    audit: auditTab,
    related: <RelatedDocumentsTab rows={relatedRows} />,
    party: relatedPartyTab,
    attachments: attachmentsTab,
    activity: timelineTab,
    notes: notesTab,
    system: systemTab,
  }

  // ── Right sidebar (§21) ─────────────────────────────────────
  return (
    <>
      {actionError && <div className="mb-3 border border-red-200 bg-red-50 rounded-md px-4 py-2 text-sm text-red-700">{actionError}</div>}
      <TransactionWorkspace
        title="Sales Invoice"
        documentNo={si.si_number}
        status={headerStatus}
        statusLabel={headerStatusLabel}
        identity={{
          name: (
            <button onClick={openCustomer} className="pxl-customer-link truncate text-left">
              {si.customer_name_snapshot || customer?.registered_name || '—'}
            </button>
          ),
        }}
        metrics={[
          { label: 'Invoice Total', value: <AmountCell amount={num(si.total_amount)} />, emphasis: true },
          { label: 'Collected', value: <AmountCell amount={collection.paid + collection.cwt} /> },
          { label: 'Balance Due', value: <AmountCell amount={collection.balance} />, emphasis: collection.balance > 0.005 },
        ]}
        meta={[
          { label: 'Collection', value: collection.status || 'Not posted', tone: collection.status === 'Paid' ? 'success' : collection.status === 'Partially Paid' ? 'warning' : collection.status === 'Open' ? 'info' : 'neutral' },
          { label: 'Lock', value: lockLabel, tone: si.status === 'draft' ? 'neutral' : 'warning' },
        ]}
        actions={actions}
        workflow={workflow}
        primary={primaryInfo}
        tabContent={tabContent}
        tabBadges={{ lines: lines.length || undefined }}
        family="sales"
        sidebarPanels={[
          { key: 'balance', title: 'Balance', content: <div className="space-y-2"><div className="flex items-baseline justify-between gap-3"><span className="pxl-field-label">Invoice Total</span><span className="font-mono text-xs font-semibold"><AmountCell amount={num(si.total_amount)} /></span></div><div className="flex items-baseline justify-between gap-3"><span className="pxl-field-label">Collected</span><span className="font-mono text-xs"><AmountCell amount={collection.paid + collection.cwt} /></span></div><div className="flex items-baseline justify-between gap-3"><span className="pxl-field-label">Balance Due</span><span className="font-mono text-sm font-bold"><AmountCell amount={collection.balance} /></span></div></div> },
          { key: 'tax', title: 'Tax', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Output VAT</span><span className="font-mono text-xs"><AmountCell amount={num(si.total_vat_amount)} /></span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Expected CWT</span><span className="font-mono text-xs"><AmountCell amount={cwt} /></span></div></div> },
          { key: 'gl', title: 'GL Preview', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Debit</span><span className="font-mono text-xs"><AmountCell amount={combinedGlDebit} /></span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Credit</span><span className="font-mono text-xs"><AmountCell amount={combinedGlCredit} /></span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Difference</span><span className={`font-mono text-xs ${Math.abs(combinedGlDifference) > 0.005 ? 'text-red-700' : 'text-green-700'}`}><AmountCell amount={combinedGlDifference} /></span></div></div> },
          { key: 'customer', title: 'Customer', content: <div><button type="button" onClick={openCustomer} className="pxl-customer-link text-left text-xs font-semibold hover:underline">{si.customer_name_snapshot || customer?.registered_name || 'Customer unavailable'}</button><div className="pxl-caption mt-1 font-mono">{si.customer_tin_snapshot ? normalizePhTin(si.customer_tin_snapshot) : 'No TIN snapshot'}</div></div> },
          { key: 'audit', title: 'Audit', content: <p className="pxl-caption">{lockLabel} · Updated {formatDateTime(si.updated_at)}</p> },
        ]}
        footer={
          <div className="flex items-center justify-between gap-4 flex-wrap">
            <span>Created {formatDateTime(si.created_at)} · Updated {formatDateTime(si.updated_at)}</span>
            <span>{lockLabel}</span>
          </div>
        }
        onBack={backToList}
        backLabel="Sales Invoices"
      />

      {showVoid && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => setShowVoid(false)} />
          <div className="relative bg-white rounded shadow-lg border border-gray-200 w-full max-w-md p-4 z-10">
            <h2 className="text-sm font-semibold text-gray-900 mb-1">Void Sales Invoice</h2>
            <p className="text-xs text-gray-500 mb-4">Voiding <span className="font-mono font-semibold">{si.si_number}</span> is permanent and posts a reversing journal entry. The SI number is never reused (BIR).</p>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Void Reason <span className="text-red-500">*</span></label>
                <select value={voidReason} onChange={e => setVoidReason(e.target.value)} className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">Select reason…</option>
                  {voidReasons.map(r => <option key={r.id} value={r.id}>{r.description}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Additional Notes</label>
                <textarea value={voidMemo} onChange={e => setVoidMemo(e.target.value)} rows={2} className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 resize-none" />
              </div>
            </div>
            {actionError && <p className="mt-2 text-xs text-red-600">{actionError}</p>}
            <div className="flex justify-end gap-2 mt-4">
              <button onClick={() => setShowVoid(false)} className="border border-gray-300 text-gray-700 px-4 py-1.5 rounded text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={doVoid} disabled={!voidReason || busy} className="bg-red-600 text-white px-4 py-1.5 rounded text-sm font-medium hover:bg-red-700 disabled:opacity-50">{busy ? 'Voiding…' : 'Void Invoice'}</button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
