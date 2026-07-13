import { useState, useEffect, useCallback, type ReactNode } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { DocumentLayout, WorkflowStrip, type DocumentTab, type ToolbarAction } from '@/components/document/DocumentLayout'
import { PrimaryInformationPanel, type InfoGroup } from '@/components/document/PrimaryInformationPanel'
import { FinancialSummaryPanel, type SummaryGroup } from '@/components/document/FinancialSummaryPanel'
import { PostingValidationPanel, readinessToChecks, type ValidationCheck } from '@/components/document/PostingValidationPanel'
import { LineGrid, type LineColumn, type LineColumnProfile } from '@/components/document/LineGrid'
import { LineDetailPanel, type DetailSection } from '@/components/document/LineDetailPanel'
import { TaxImpactPanel } from '@/components/document/TaxImpactPanel'
import { RelatedDocumentsTab, type RelatedDocRow } from '@/components/document/RelatedDocumentsTab'
import { ErpSectionHeader, CompactEmptyState, ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH, ERP_TD, ERP_TD_NUM } from '@/components/document/ErpSection'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { AuditTrailSection, StatusBadge, AmountCell, DateCell, EmptyState } from '@/components/ui/shared'

// Stable identity so the readiness effect doesn't re-run each render.
const SI_REQUIRED_CONFIG: ConfigField[] = ['ar_account_id', 'vat_payable_account_id']

// ─────────────────────────────────────────────────────────────
// Sales Invoice — CANONICAL routed document workspace and the
// REFERENCE implementation of the PXL Standard Transaction
// Workspace (DEC-013/DEC-015). Single viewing/review/lifecycle
// surface for a saved invoice (deep-linkable, UI Principle 38).
// Draft create/edit form relocation is the final consolidation step.
// ─────────────────────────────────────────────────────────────

type SIStatus = 'draft' | 'approved' | 'posted' | 'cancelled'

type SIRow = {
  id: string; company_id: string; branch_id: string
  si_number: string; date: string; customer_id: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  customer_address_snapshot: string; payment_terms_id: string | null
  due_date: string | null; currency_code: string
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
  created_by: string | null; updated_by: string | null
  created_at: string; updated_at: string
}

type CustomerMaster = {
  id: string; registered_name: string; tin: string; tin_branch_code: string | null
  registered_address: string; delivery_address: string | null
  contact_person: string | null; email: string | null; phone_number: string | null
  default_tax_type: string; is_withholding_agent: boolean
  default_terms_id: string | null; credit_limit: number | null
  customer_code: string; customer_group: string | null; business_style: string | null
  trade_name: string | null; created_at: string | null; is_active: boolean | null
}

type AccountRef = { code: string; name: string }
type ItemRef = { code: string; description: string; notes: string | null }
type UomRef = { code: string; description: string }
type VatRef = { code: string; classification: string; rate: number }
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
const TAX_TYPE_LABEL: Record<string, string> = {
  vat_registered: 'VAT registered', non_vat: 'Non-VAT', vat_exempt: 'VAT exempt', zero_rated: 'Zero-rated',
}
const formatDateTime = (v?: string | null) => (v ? new Date(v).toLocaleString('en-PH') : 'Not recorded')
const num = (v: unknown) => Number(v ?? 0)
const erpTabSection = (title: string, description: ReactNode, children: ReactNode) => (
  <section className="bg-white border border-gray-200 rounded p-3 space-y-2">
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
  const [branchName, setBranchName] = useState('')
  const [seriesName, setSeriesName] = useState('')
  const [accentColor, setAccentColor] = useState('#14532d')
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
    const [lineRes, accRes, itemRes, uomRes, vatRes, brRes, termRes, custRes, jeRes, rlRes, reasonRes, apprRes, seriesRes, companyRes, customerInvoiceRes, customerReceiptRes, agingRes] = await Promise.all([
      supabase.from('sales_invoice_lines').select('*').eq('sales_invoice_id', id).order('line_number'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', inv.company_id),
      supabase.from('items').select('id,item_code,description,description_long').eq('company_id', inv.company_id),
      supabase.from('units_of_measure').select('id,uom_code,description').eq('company_id', inv.company_id),
      supabase.from('vat_codes').select('id,vat_code,vat_classification,tax_codes(rate)'),
      supabase.from('branches').select('id,branch_name').eq('id', inv.branch_id).maybeSingle(),
      supabase.from('payment_terms').select('id,term_name').eq('company_id', inv.company_id),
      inv.customer_id ? supabase.from('customers').select('*').eq('id', inv.customer_id).maybeSingle() : Promise.resolve({ data: null }),
      supabase.from('journal_entries').select('id,je_number,je_date,status,total_debit')
        .eq('company_id', inv.company_id).eq('reference_doc_type', 'SI').eq('reference_doc_id', inv.id).order('je_date'),
      supabase.from('receipt_lines').select('receipt_id,payment_amount,cwt_amount').eq('invoice_id', inv.id),
      supabase.from('void_reason_codes').select('id,code,description').eq('is_active', true).order('code'),
      supabase.from('approval_instances').select('*').eq('source_document_id', inv.id).order('step_sequence'),
      supabase.from('number_series').select('prefix,number_length,reset_frequency').eq('company_id', inv.company_id).eq('branch_id', inv.branch_id).eq('document_code', 'SI').eq('is_active', true).limit(1).maybeSingle(),
      supabase.from('companies').select('*').eq('id', inv.company_id).maybeSingle(),
      supabase.from('sales_invoices').select('id,si_number,date,due_date,total_amount,status').eq('company_id', inv.company_id).eq('customer_id', inv.customer_id).order('date', { ascending: false }),
      supabase.from('receipts').select('id,receipt_number,receipt_date,total_amount,total_cwt,status').eq('company_id', inv.company_id).eq('customer_id', inv.customer_id).eq('status', 'posted').order('receipt_date', { ascending: false }),
      supabase.rpc('fn_ar_aging_asof', { p_company_id: inv.company_id, p_as_of: todayIso, p_customer_id: inv.customer_id }),
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
    setBranchName((brRes.data as { branch_name?: string } | null)?.branch_name ?? '')
    const series = seriesRes.data as { prefix?: string | null; number_length?: number; reset_frequency?: string } | null
    setSeriesName(series ? `${series.prefix || 'SI'} · ${series.number_length ?? 6} digits · ${series.reset_frequency ?? 'never'} reset` : '')
    const company = companyRes.data as Record<string, unknown> | null
    setAccentColor(typeof company?.workspace_accent_color === 'string' ? company.workspace_accent_color : '#14532d')
    const tmap: Record<string, string> = {}
    for (const t of termRes.data ?? []) tmap[t.id] = t.term_name
    setTermsName(tmap)
    setCustomer((custRes.data as CustomerMaster | null) ?? null)
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
    if (receiptIds.length > 0) {
      const { data: rcpts } = await supabase.from('receipts').select('id,status').in('id', receiptIds)
      const posted = new Set((rcpts ?? []).filter(r => r.status === 'posted').map(r => r.id))
      for (const rl of rls) if (posted.has(rl.receipt_id)) { paid += num(rl.payment_amount); cwtColl += num(rl.cwt_amount) }
    }
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
      { key: 'si', relationship: 'This document', docType: 'Sales Invoice', direction: 'current', number: inv.si_number, date: inv.date, status: statusToShared[inv.status], amount: num(inv.total_amount) },
      receiptIds.length > 0
        ? { key: 'or', relationship: 'Collection', docType: 'Official Receipt', direction: 'downstream', number: `${receiptIds.length} applied`, status: 'posted', href: '/receipts' }
        : { key: 'or', relationship: 'Collection', docType: 'Official Receipt', direction: 'downstream', action: posted ? { label: 'Create Receipt', href: '/receipts' } : null },
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
  const cwt = num(si.cwt_amount_expected)
  const lockLabel = si.status === 'draft' ? 'Editable' : 'Frozen'
  const postingLabel = si.status === 'posted' ? 'Posted' : si.status === 'cancelled' ? 'Voided' : 'Unposted'

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
    actions.push({ key: 'edit', label: 'Edit', group: 'more', onClick: backToList, disabled: busy, title: 'Draft editing opens in the register editor (form relocation pending)' })
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
  const availableCredit = customer?.credit_limit != null && customerOutstanding != null
    ? num(customer.credit_limit) - customerOutstanding
    : null
  const notAssigned = (provenance: string) => ({ value: <span className="text-gray-400">Not assigned</span>, provenance })
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
    ...(si.reference ? [{ label: 'Reference', value: si.reference }] : []),
  ]
  const primaryGroups: InfoGroup[] = [
    {
      key: 'doc', title: 'Document Information', fields: documentFields,
    },
    {
      key: 'cust', title: 'Customer Information', fields: [
        { label: 'Customer', value: customerLink, wide: true, provenance: 'opens Customer master' },
        { label: 'Customer Code', value: customer?.customer_code || '—', provenance: 'from Customer master' },
        { label: 'TIN', value: si.customer_tin_snapshot || customer?.tin || '—', provenance: 'snapshot / Customer master' },
        { label: 'VAT Classification', value: customer ? (TAX_TYPE_LABEL[customer.default_tax_type] ?? customer.default_tax_type) : '—', provenance: 'from Customer master' },
      ],
    },
    {
      key: 'ctx', title: 'Sales Context', fields: [
        { label: 'Salesperson', ...notAssigned('Salesperson is not yet stored on Sales Invoice') },
        { label: 'Project', ...notAssigned('Project is not yet stored on Sales Invoice') },
        { label: 'Cost Center', ...notAssigned('Cost Center master exists but is not yet linked') },
        { label: 'Department', ...notAssigned('Department master exists but is not yet linked') },
      ],
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
    { key: 'department', header: 'Department', group: 'dimensions', defaultWidth: 118, render: () => emptyLineValue },
    { key: 'cost_center', header: 'Cost Center', group: 'dimensions', defaultWidth: 118, render: () => emptyLineValue },
    { key: 'project', header: 'Project', group: 'dimensions', defaultWidth: 118, render: () => emptyLineValue },
    { key: 'warehouse', header: 'Warehouse', group: 'inventory', defaultWidth: 116, render: () => emptyLineValue },
    { key: 'branch', header: 'Branch', group: 'dimensions', defaultWidth: 130, sortValue: () => branchName, filterValue: () => branchName, exportValue: () => branchName, render: () => branchName || '—' },
    { key: 'location', header: 'Location', group: 'inventory', defaultWidth: 112, render: () => emptyLineValue },
    { key: 'cost', header: 'Cost', group: 'inventory', align: 'right', defaultWidth: 96, render: () => emptyLineValue },
    { key: 'inventory_account', header: 'Inventory Account', group: 'inventory', defaultWidth: 150, render: () => emptyLineValue },
    { key: 'remarks', header: 'Remarks', group: 'reference', defaultWidth: 120, render: () => emptyLineValue },
    { key: 'reference', header: 'Reference', group: 'reference', defaultWidth: 130, sortValue: () => si.reference || '', filterValue: () => si.reference || '', exportValue: () => si.reference || '', render: () => si.reference || emptyLineValue },
    { key: 'source_doc', header: 'Source Document', group: 'audit', defaultWidth: 140, sortValue: () => si.reference || '', filterValue: () => si.reference || '', exportValue: () => si.reference || '', render: () => si.reference || emptyLineValue },
    { key: 'journal_entry', header: 'Journal Entry', group: 'audit', defaultWidth: 130, sortValue: () => si.journal_entry_id || '', filterValue: () => si.journal_entry_id || '', exportValue: () => si.journal_entry_id || '', render: () => si.journal_entry_id ? <span className="font-mono">{si.journal_entry_id.slice(0, 8)}…</span> : emptyLineValue },
    { key: 'posting_rule', header: 'Posting Rule', group: 'audit', defaultWidth: 160, sortValue: linePostingRule, filterValue: linePostingRule, exportValue: linePostingRule, render: line => linePostingRule(line) },
    { key: 'created_by', header: 'Created By', group: 'audit', defaultWidth: 150, sortValue: line => line.created_by || '', filterValue: line => line.created_by || '', exportValue: line => line.created_by || '', render: line => line.created_by ? <span className="font-mono">{line.created_by}</span> : emptyLineValue },
    { key: 'created_date', header: 'Created Date', group: 'audit', defaultWidth: 150, sortValue: line => line.created_at, filterValue: line => formatDateTime(line.created_at), exportValue: line => line.created_at, render: line => formatDateTime(line.created_at) },
    { key: 'uuid', header: 'UUID', group: 'system', defaultWidth: 160, sortValue: line => line.id, filterValue: line => line.id, exportValue: line => line.id, render: line => <span className="font-mono">{line.id.slice(0, 8)}…</span> },
    { key: 'status', header: 'Status', group: 'audit', defaultWidth: 100, sortValue: () => si.status, filterValue: () => si.status, exportValue: () => si.status, render: () => <StatusBadge status={statusToShared[si.status]} label={si.status} /> },
  ]
  const lineProfiles: LineColumnProfile[] = [
    { key: 'default', label: 'Default', columnKeys: ['no', 'item_code', 'desc', 'qty', 'uom', 'price', 'disc_pct', 'net', 'vat_code', 'vat_amt', 'total'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'accounting', label: 'Accounting', columnKeys: ['no', 'item_code', 'desc', 'acct', 'department', 'cost_center', 'branch', 'project', 'vat_code', 'vat_amt', 'ewt_code', 'ewt_amt', 'net', 'total'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'tax', label: 'Tax', columnKeys: ['no', 'item_code', 'desc', 'vat_code', 'atc', 'tax_base', 'vat_pct', 'vat_amt', 'ewt_code', 'ewt_amt', 'tax_class'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'audit', label: 'Audit', columnKeys: ['no', 'item_code', 'desc', 'source_doc', 'journal_entry', 'posting_rule', 'created_by', 'created_date', 'uuid', 'status', 'acct', 'branch'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'inventory', label: 'Inventory', columnKeys: ['no', 'item_code', 'item_desc', 'desc', 'warehouse', 'uom', 'qty', 'cost', 'inventory_account', 'location'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
    { key: 'sales', label: 'Sales', columnKeys: ['no', 'item_code', 'item_desc', 'desc', 'qty', 'uom', 'price', 'disc_pct', 'disc_amt', 'net', 'total'], pinnedColumnKeys: ['no', 'item_code', 'desc'], density: 'compact' },
  ]
  const selectedLine = lines.find(line => line.id === selectedLineId) ?? null
  const lineDetailSections: DetailSection[] = selectedLine ? [
    { key: 'revrec', title: 'Revenue Recognition', fields: [
      { label: 'Schedule', value: 'Not linked' }, { label: 'Revenue Account', value: accountLabel(selectedLine.revenue_account_id) },
    ] },
    { key: 'serial', title: 'Serial Numbers', fields: [{ label: 'Serials', value: 'Not recorded' }] },
    { key: 'lots', title: 'Lots', fields: [{ label: 'Lots', value: 'Not recorded' }] },
    { key: 'allocation', title: 'Inventory Allocation', fields: [
      { label: 'Warehouse', value: 'Not assigned' }, { label: 'Allocation', value: 'Not recorded' },
    ] },
    { key: 'dimensions', title: 'Dimensions', fields: [
      { label: 'Branch', value: branchName || '—' }, { label: 'Department', value: 'Not assigned' },
      { label: 'Cost Center', value: 'Not assigned' }, { label: 'Project', value: 'Not assigned' },
    ] },
    { key: 'tax', title: 'Tax Breakdown', fields: [
      { label: 'VAT Code', value: selectedLine.vat_code_id ? vatCodes[selectedLine.vat_code_id]?.code ?? '—' : '—' },
      { label: 'VAT Base', value: <AmountCell amount={num(selectedLine.net_amount)} /> },
      { label: 'VAT Rate', value: `${num(selectedLine.vat_code_id ? vatCodes[selectedLine.vat_code_id]?.rate : 0)}%` },
      { label: 'VAT Amount', value: <AmountCell amount={num(selectedLine.vat_amount)} /> },
    ] },
    { key: 'audit', title: 'Audit Information', fields: [
      { label: 'Created', value: formatDateTime(selectedLine.created_at) },
      { label: 'Last Modified', value: formatDateTime(selectedLine.updated_at) },
      { label: 'Created By', value: selectedLine.created_by || '—' },
    ] },
    { key: 'source', title: 'Source References', fields: [{ label: 'Source Document', value: 'Not linked' }, { label: 'Reference', value: si.reference || '—' }] },
    { key: 'rule', title: 'Posting Rule Used', fields: [
      { label: 'Account Source', value: selectedLine.revenue_account_id ? 'Item / document line account' : 'Unmapped' },
      { label: 'Account', value: accountLabel(selectedLine.revenue_account_id) },
    ] },
    { key: 'related', title: 'Related Documents', fields: [{ label: 'Line-level Links', value: 'Not linked' }] },
    { key: 'notes', title: 'Item Notes', fields: [{ label: 'Notes', value: selectedLine.item_id ? items[selectedLine.item_id]?.notes || 'No item notes' : 'No item selected' }] },
  ] : []
  const linesTab = erpTabSection(
    'Lines',
    'Transaction line items, tax codes, posting accounts, and dimensions.',
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
      <p className="text-[10px] text-gray-400 mt-1.5">Click any row to inspect recognition, inventory, dimensions, tax, audit, source, posting rule, links, and item notes.</p>
    </>,
  )

  // ── Financial Summary (full, §10) ───────────────────────────
  const summaryFull: SummaryGroup[] = [
    { key: 'main', rows: [
      { key: 'gross-sales', label: 'Gross Sales', value: subtotal },
      { key: 'discounts', label: 'Discounts', value: discounts, variant: 'muted', paren: true },
      { key: 'net-sales', label: 'Net Sales', value: netOfVat, variant: 'strong', divider: true },
      { key: 'vat', label: 'VAT', value: num(si.total_vat_amount) },
      { key: 'zero', label: 'Zero Rated', value: num(si.total_zero_rated_amount), variant: 'muted' },
      { key: 'exempt', label: 'Exempt', value: num(si.total_exempt_amount), variant: 'muted' },
      { key: 'ewt', label: 'EWT / Expected CWT', value: cwt, variant: 'muted', paren: cwt > 0 },
      { key: 'invoice-total', label: 'Invoice Total', value: num(si.total_amount), variant: 'total', divider: true },
    ] },
    { key: 'collections', rows: [
      { key: 'collected', label: 'Collections', value: collection.paid + collection.cwt },
      { key: 'remaining', label: 'Remaining Balance', value: collection.balance, variant: 'total', divider: true },
    ] },
    { key: 'recognition', rows: [
      { key: 'realized', label: 'Realized Revenue', value: <span className="text-gray-400">Not tracked</span>, variant: 'muted' },
      { key: 'deferred', label: 'Deferred Revenue', value: <span className="text-gray-400">Not tracked</span>, variant: 'muted' },
      { key: 'rounding', label: 'Rounding', value: <span className="text-gray-400">Not stored</span>, variant: 'muted' },
      { key: 'currency-difference', label: 'Currency Difference', value: <span className="text-gray-400">Not stored</span>, variant: 'muted' },
    ], note: cwt > 0 ? 'Expected CWT is informational and settles through the customer’s BIR Form 2307; it does not reduce invoice revenue.' : undefined },
  ]
  const financialTab = <FinancialSummaryPanel title="Financial Summary" groups={summaryFull} />

  const glTab = <GLImpactPanel companyId={companyId} sourceDocType="SI" sourceDocId={si.id} previewRows={[]} />
  const taxTab = <TaxImpactPanel sourceDocType="SI" sourceDocId={si.id} fallbackLabel="Output VAT"
    fallbackBase={num(si.total_taxable_amount)} fallbackRate={12} fallbackAmount={num(si.total_vat_amount)} />

  // ── Posting Validation ──────────────────────────────────────
  const postable = si.status === 'draft' || si.status === 'approved'
  const readinessState = (pattern: RegExp): ValidationCheck['state'] =>
    readiness.loading ? 'pending' : readiness.blockers.some(blocker => pattern.test(blocker)) ? 'blocked' : 'ok'
  const arithmeticBalanced = Math.abs(netOfVat + num(si.total_vat_amount) - num(si.total_amount)) <= 0.01
  const docChecks: ValidationCheck[] = [
    { key: 'balanced', label: 'Balanced', state: arithmeticBalanced ? 'ok' : 'blocked', detail: 'Net sales plus VAT agrees to the invoice total.' },
    { key: 'period', label: 'Period Open', state: readinessState(/period|fiscal/i) },
    { key: 'branch', label: 'Branch Active', state: branchName ? readinessState(/branch/i) : 'blocked' },
    { key: 'series', label: 'Series Valid', state: si.si_number && seriesName ? readinessState(/series|number/i) : 'blocked' },
    { key: 'tax', label: 'Tax Valid', state: lines.every(line => line.vat_code_id || num(line.vat_amount) === 0) ? 'ok' : 'blocked' },
    { key: 'inventory', label: 'Inventory Posted', state: 'info', detail: 'No inventory posting reference is stored on Sales Invoice lines.' },
    { key: 'cost', label: 'Cost Posted', state: 'info', detail: 'No cost posting reference is stored on Sales Invoice lines.' },
    { key: 'approval', label: 'Approval Passed', state: si.status === 'draft' ? 'pending' : si.status === 'approved' || si.status === 'posted' ? 'ok' : 'info' },
    { key: 'engine', label: 'Posting Engine Version', state: 'info', detail: 'The runtime version is not exposed by the current posting RPC.' },
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
        ? 'Live preflight — each check mirrors a server-side validation the post RPC enforces (blueprint §11). Approval SoD surfaces here when multi-step routing lands.'
        : 'Derived from the saved document. The setup preflight applies to postable (draft/approved) invoices.'} />
  )

  // ── Workflow tab ────────────────────────────────────────────
  const workflowRows = [
    { stage: 'Draft', status: si.created_at ? 'Completed' : 'Pending', date: si.created_at, actor: si.created_by },
    { stage: 'Approved', status: si.approved_at ? 'Completed' : si.status === 'draft' ? 'Pending' : 'Not recorded', date: si.approved_at, actor: si.approved_by },
    { stage: 'Posted', status: si.posted_at ? 'Completed' : si.status === 'cancelled' ? 'Voided' : 'Pending', date: si.posted_at, actor: si.posted_by },
    { stage: 'Collection', status: collection.status || 'Not posted', date: null, actor: null },
    { stage: 'Lock', status: lockLabel, date: si.updated_at, actor: si.updated_by },
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
              {['Stage', 'Status', 'Date', 'Actor'].map(label => (
                <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {workflowRows.map(row => (
              <tr key={row.stage}>
                <td className={`${ERP_TD} text-gray-800`}>{row.stage}</td>
                <td className={`${ERP_TD} text-gray-600`}>{row.status}</td>
                <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.date ? formatDateTime(row.date) : '—'}</td>
                <td className={`${ERP_TD} font-mono text-gray-500 truncate`}>{row.actor || '—'}</td>
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
            {['Level', 'Approver', 'Role', 'Action', 'Remarks', 'Date', 'Electronic Signature'].map(label => (
              <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {approvals.map(row => (
            <tr key={row.id}>
              <td className={ERP_TD}>{row.step_sequence}</td>
              <td className={`${ERP_TD} font-mono text-gray-600`}>{row.actual_approver_id || row.required_approver_id || 'Pending'}</td>
              <td className={`${ERP_TD} text-gray-600`}>{row.required_approver_type}</td>
              <td className={ERP_TD}><StatusBadge status={row.status === 'approved' ? 'approved' : row.status === 'rejected' ? 'error' : 'pending'} label={row.status} /></td>
              <td className={`${ERP_TD} text-gray-600`}>{row.remarks || '—'}</td>
              <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{formatDateTime(row.acted_at || row.submitted_at)}</td>
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
    { label: 'Created', value: formatDateTime(si.created_at) },
    { label: 'Last edited', value: formatDateTime(si.updated_at) },
    { label: 'Created by', value: si.created_by ? <span className="font-mono" title={si.created_by}>{si.created_by}</span> : '—' },
    { label: 'Last modified by', value: si.updated_by ? <span className="font-mono" title={si.updated_by}>{si.updated_by}</span> : '—' },
    { label: 'Approved', value: formatDateTime(si.approved_at) },
    { label: 'Posted', value: formatDateTime(si.posted_at) },
    { label: 'Lock status', value: lockLabel },
  ]
  const auditTab = erpTabSection(
    'Audit',
    'Chronological document facts and system audit trail.',
    <div className="space-y-2">
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-7 gap-x-3 gap-y-2">
        {auditFacts.map(f => (
          <div key={f.label}><div className="text-[10px] uppercase tracking-wide text-gray-400 mb-0.5">{f.label}</div><div className="text-xs text-gray-700">{f.value}</div></div>
        ))}
      </div>
      <AuditTrailSection tableName="sales_invoices" recordId={si.id} initiallyExpanded />
    </div>,
  )

  // ── Activity Timeline (lifecycle facts; semantic events pending PXL-DA-016) ──
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
      <li className="ml-4 text-[11px] text-gray-400">Semantic event stream (edited/printed/emailed) arrives with PXL-DA-016 transaction_events.</li>
    </ol>,
  )

  // ── Notes ───────────────────────────────────────────────────
  const notesTab = erpTabSection(
    'Notes',
    'Internal, customer, accounting, and collection notes.',
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
      {[
        ['Internal Notes', null],
        ['Customer Notes', si.memo],
        ['Accounting Notes', null],
        ['Collection Notes', null],
      ].map(([label, value]) => (
        <section key={label} className="border border-gray-200 rounded p-3 min-h-20">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500 mb-2">{label}</div>
          <div className="text-xs text-gray-700 whitespace-pre-wrap">{value || <span className="text-gray-400">No notes recorded.</span>}</div>
        </section>
      ))}
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
          {['File', 'Type', 'Uploaded By', 'Date', 'Preview', 'Download', 'OCR Status'].map(label => (
            <th key={label} className={`${ERP_TH} text-left`}>{label}</th>
          ))}
        </tr></thead>
        <tbody><tr><td colSpan={7} className={ERP_EMPTY_CELL}>No attachments linked to this invoice.</td></tr></tbody>
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
  const relatedPartySection = (title: string, fields: ReactNode, className = '') => (
    <section className={`border border-gray-200 rounded p-3 min-w-0 ${className}`}>
      <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500 mb-2">{title}</div>
      {fields}
    </section>
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
          ['TIN', si.customer_tin_snapshot || customer.tin || '—'],
          ['TIN Branch', customer.tin_branch_code || '—'],
          ['VAT Classification', customerTaxLabel],
          ['Withholding Status', customer.is_withholding_agent ? 'Withholding agent' : 'Not a withholding agent'],
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
        ]))}
        {relatedPartySection('Addresses', relatedPartyGrid([
          ['Registered Address', si.customer_address_snapshot || customer.registered_address || '—', true],
          ['Delivery Address', customer.delivery_address || '—', true],
        ]))}
        {relatedPartySection('Payment Information', relatedPartyGrid([
          ['Default Terms', termLabel(customer.default_terms_id || si.payment_terms_id)],
          ['Payment Method', mutedValue('Selected at receipt')],
          ['Price List', mutedValue('Not assigned')],
          ['Delivery Terms', mutedValue('Not assigned')],
        ]))}
        {relatedPartySection('Sales Information', relatedPartyGrid([
          ['Sales Territory', mutedValue('Not assigned')],
          ['Industry', mutedValue('Not assigned')],
          ['Price Level', mutedValue('Not assigned')],
          ['Customer Group', customer.customer_group || '—'],
        ]))}
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
        ))}
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
        ))}
      </div>
    </div>
  ),
  )

  // ── System ──────────────────────────────────────────────────
  const systemTab = erpTabSection(
    'System',
    'Technical identifiers and engine metadata for support and audit review.',
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-xs">
      {[
        ['Record ID', si.id], ['Database ID', si.id], ['Company ID', si.company_id], ['Branch ID', si.branch_id],
        ['Customer ID', si.customer_id], ['Fiscal Period ID', si.fiscal_period_id || '—'],
        ['Journal Entry ID', si.journal_entry_id || '—'], ['Source Module', 'Sales'], ['Source Type', 'SI'],
        ['Document Series', seriesName || '—'],
        ['Posting RPC', 'fn_post_sales_invoice'], ['Void RPC', 'fn_void_sales_invoice'],
        ['Posting Engine Version', 'Not exposed'], ['Tax Engine Version', 'Not exposed'],
        ['Document Hash', 'Not available'], ['Migration Version', 'Not exposed'],
        ['Tax Ledger', 'tax_detail_entries (source_doc_type=SI)'], ['Lock State', lockLabel],
        ['Created Timestamp', si.created_at], ['Updated Timestamp', si.updated_at],
      ].map(([k, v]) => (
        <div key={k} className="flex justify-between gap-4 py-1 border-b border-gray-50">
          <span className="text-gray-400">{k}</span><span className="font-mono text-gray-600 truncate" title={String(v)}>{v}</span>
        </div>
      ))}
    </div>,
  )

  const tabs: DocumentTab[] = [
    { key: 'lines', label: 'Lines', badge: lines.length || undefined, content: linesTab },
    { key: 'financial', label: 'Financial', content: financialTab },
    { key: 'gl', label: 'GL Impact', content: glTab },
    { key: 'tax', label: 'Tax Impact', content: taxTab },
    { key: 'validation', label: 'Validation', content: validationTab },
    { key: 'workflow', label: 'Workflow', content: workflowTab },
    { key: 'approval', label: 'Approval', content: approvalTab },
    { key: 'audit', label: 'Audit', content: auditTab },
    { key: 'related', label: 'Related Docs', content: <RelatedDocumentsTab rows={relatedRows} /> },
    { key: 'party', label: 'Related Party', content: relatedPartyTab },
    { key: 'attachments', label: 'Attachments', content: attachmentsTab },
    { key: 'timeline', label: 'Activity', content: timelineTab },
    { key: 'notes', label: 'Notes', content: notesTab },
    { key: 'system', label: 'System', content: systemTab },
  ]

  // ── Right sidebar (§21) ─────────────────────────────────────
  return (
    <>
      {actionError && <div className="mb-3 border border-red-200 bg-red-50 rounded-md px-4 py-2 text-sm text-red-700">{actionError}</div>}
      <DocumentLayout
        title="Sales Invoice"
        documentNo={si.si_number}
        status={si.status === 'posted' ? 'posted' : si.status === 'cancelled' ? 'error' : 'draft'}
        statusLabel={postingLabel}
        identity={{
          name: (
            <button onClick={openCustomer} className="text-white hover:underline text-left truncate">
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
        primary={primaryInfo}
        tabs={tabs}
        accentColor={accentColor}
        footer={
          <div className="flex items-center justify-between gap-4 flex-wrap">
            <span>Created {formatDateTime(si.created_at)} · Updated {formatDateTime(si.updated_at)}</span>
            <span className="font-mono">UUID {si.id}</span>
          </div>
        }
        onBack={backToList}
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
