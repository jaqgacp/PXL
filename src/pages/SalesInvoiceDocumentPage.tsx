import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { DocumentLayout, type DocumentTab, type ToolbarAction } from '@/components/document/DocumentLayout'
import { PrimaryInformationPanel, type InfoGroup } from '@/components/document/PrimaryInformationPanel'
import { FinancialSummaryPanel, type SummaryGroup } from '@/components/document/FinancialSummaryPanel'
import { PostingValidationPanel, readinessToChecks, type ValidationCheck } from '@/components/document/PostingValidationPanel'
import { LineGrid, type LineColumn } from '@/components/document/LineGrid'
import { LineDetailPanel, type DetailSection } from '@/components/document/LineDetailPanel'
import { TaxImpactPanel } from '@/components/document/TaxImpactPanel'
import { RelatedDocumentsTab, type RelatedDocRow } from '@/components/document/RelatedDocumentsTab'
import { SidebarCard, CardRow } from '@/components/document/SidebarCard'
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
  approved_at: string | null; posted_at: string | null
  created_at: string; updated_at: string
}

type LineRow = {
  id: string; line_number: number; item_id: string | null; description: string
  quantity: number; uom_id: string | null; unit_price: number
  discount_percent: number; discount_amount: number
  net_amount: number; vat_code_id: string | null; vat_amount: number; total_amount: number
  revenue_account_id: string | null
}

type CustomerMaster = {
  id: string; registered_name: string; tin: string; tin_branch_code: string | null
  registered_address: string; delivery_address: string | null
  contact_person: string | null; email: string | null; phone_number: string | null
  default_tax_type: string; is_withholding_agent: boolean
  default_terms_id: string | null; credit_limit: number | null
}

type AccountRef = { code: string; name: string }
type VoidReason = { id: string; code: string; description: string }
type Collection = { paid: number; cwt: number; balance: number; receiptCount: number; status: string | null }
type ApprovalRow = { id: string; status: string; required_approver_type?: string; actual_approver_id?: string | null; source_document_no?: string; created_at?: string; approved_at?: string | null; decision_comments?: string | null }

const statusToShared: Record<SIStatus, string> = {
  draft: 'draft', approved: 'approved', posted: 'posted', cancelled: 'error',
}
const TAX_TYPE_LABEL: Record<string, string> = {
  vat_registered: 'VAT registered', non_vat: 'Non-VAT', vat_exempt: 'VAT exempt', zero_rated: 'Zero-rated',
}
const formatDateTime = (v?: string | null) => (v ? new Date(v).toLocaleString('en-PH') : 'Not recorded')
const num = (v: unknown) => Number(v ?? 0)

export default function SalesInvoiceDocumentPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { companyId } = useAppCtx()

  const [si, setSi] = useState<SIRow | null>(null)
  const [lines, setLines] = useState<LineRow[]>([])
  const [accounts, setAccounts] = useState<Record<string, AccountRef>>({})
  const [branchName, setBranchName] = useState('')
  const [termsName, setTermsName] = useState<Record<string, string>>({})
  const [customer, setCustomer] = useState<CustomerMaster | null>(null)
  const [collection, setCollection] = useState<Collection>({ paid: 0, cwt: 0, balance: 0, receiptCount: 0, status: null })
  const [approval, setApproval] = useState<ApprovalRow | null>(null)
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

    const [lineRes, accRes, brRes, termRes, custRes, jeRes, rlRes, reasonRes, apprRes] = await Promise.all([
      supabase.from('sales_invoice_lines').select('*').eq('sales_invoice_id', id).order('line_number'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', inv.company_id),
      supabase.from('branches').select('id,branch_name').eq('id', inv.branch_id).maybeSingle(),
      supabase.from('payment_terms').select('id,term_name').eq('company_id', inv.company_id),
      inv.customer_id ? supabase.from('customers').select('*').eq('id', inv.customer_id).maybeSingle() : Promise.resolve({ data: null }),
      supabase.from('journal_entries').select('id,je_number,je_date,status,total_debit')
        .eq('company_id', inv.company_id).eq('reference_doc_type', 'SI').eq('reference_doc_id', inv.id).order('je_date'),
      supabase.from('receipt_lines').select('receipt_id,payment_amount,cwt_amount').eq('invoice_id', inv.id),
      supabase.from('void_reason_codes').select('id,code,description').eq('is_active', true).order('code'),
      supabase.from('approval_instances').select('*').eq('source_document_id', inv.id).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    ])

    setLines((lineRes.data ?? []) as unknown as LineRow[])
    const map: Record<string, AccountRef> = {}
    for (const a of accRes.data ?? []) map[a.id] = { code: a.account_code, name: a.account_name }
    setAccounts(map)
    setBranchName((brRes.data as { branch_name?: string } | null)?.branch_name ?? '')
    const tmap: Record<string, string> = {}
    for (const t of termRes.data ?? []) tmap[t.id] = t.term_name
    setTermsName(tmap)
    setCustomer((custRes.data as CustomerMaster | null) ?? null)
    setVoidReasons((reasonRes.data ?? []) as VoidReason[])
    setApproval((apprRes.data as ApprovalRow | null) ?? null)

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

  if (loading) return <div className="py-16 text-center text-sm text-gray-400">Loading Sales Invoice…</div>
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
  const expectedNet = num(si.total_amount) - cwt
  const lockLabel = si.status === 'draft' ? 'Editable' : 'Frozen'
  const postingLabel = si.status === 'posted' ? 'Posted' : si.status === 'cancelled' ? 'Voided' : 'Unposted'

  // ── Workflow strip (full lifecycle) ─────────────────────────
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
    actions.push({ key: 'edit', label: 'Edit', variant: 'primary', onClick: backToList, disabled: busy, title: 'Draft editing opens in the register editor (form relocation pending)' })
    actions.push({ key: 'approve', label: 'Submit for Approval', onClick: () => runAction('fn_approve_sales_invoice', 'Approve'), disabled: busy })
  }
  if (si.status === 'approved') {
    actions.push({ key: 'post', label: 'Post Invoice', variant: 'primary', onClick: () => runAction('fn_post_sales_invoice', 'Post'), disabled: busy })
    actions.push({ key: 'revert', label: 'Return to Draft', group: 'more', onClick: () => runAction('fn_revert_si_to_draft', 'Return to draft'), disabled: busy })
  }
  if (si.status === 'posted') {
    actions.push({ key: 'receipt', label: 'Create Receipt', variant: 'primary', onClick: () => navigate('/receipts') })
    actions.push({ key: 'cm', label: 'Create Credit Memo', group: 'more', onClick: () => navigate('/credit-memos') })
    actions.push({ key: 'void', label: 'Void', group: 'more', variant: 'danger', onClick: () => setShowVoid(true), disabled: busy })
  }
  actions.push({ key: 'print', label: 'Print', group: 'more', onClick: () => window.print() })
  actions.push({ key: 'je', label: 'Open Journal Entry', group: 'more', onClick: () => navigate(`/accounting-trace?sourceType=SI&sourceId=${si.id}`) })
  actions.push({ key: 'refresh', label: 'Refresh', group: 'more', onClick: load, disabled: busy })

  // ── Primary Information (§5) ─────────────────────────────────
  const termLabel = (tid: string | null) => (tid && termsName[tid]) || '—'
  const primaryGroups: InfoGroup[] = [
    {
      key: 'doc', title: 'Document Information',
      fields: [
        { label: 'Invoice No.', value: si.si_number },
        { label: 'Invoice Date', value: <DateCell date={si.date} /> },
        { label: 'Due Date', value: si.due_date ? <DateCell date={si.due_date} /> : '—' },
        { label: 'Branch', value: branchName || '—' },
        { label: 'Currency', value: si.currency_code },
        { label: 'Payment Terms', value: termLabel(si.payment_terms_id), provenance: 'from Customer / document' },
        { label: 'Reference', value: si.reference || '—' },
        { label: 'Source Type', value: 'SI (manual)' },
      ],
    },
    {
      key: 'cust', title: 'Customer Information',
      fields: [
        { label: 'Customer', value: si.customer_name_snapshot, provenance: 'snapshot at save' },
        { label: 'TIN', value: si.customer_tin_snapshot || '—', provenance: 'snapshot at save' },
        { label: 'Tax Profile', value: customer ? (TAX_TYPE_LABEL[customer.default_tax_type] ?? customer.default_tax_type) : '—', provenance: 'from Customer master' },
        { label: 'Withholding', value: customer ? (customer.is_withholding_agent ? 'Withholding agent' : 'Not a withholding agent') : '—', provenance: 'from Customer master' },
        { label: 'Contact', value: customer?.contact_person || '—', provenance: 'from Customer master' },
        { label: 'Email / Phone', value: [customer?.email, customer?.phone_number].filter(Boolean).join(' · ') || '—', provenance: 'from Customer master' },
        { label: 'Registered Address', value: si.customer_address_snapshot || customer?.registered_address || '—', wide: true, provenance: 'snapshot at save' },
      ],
    },
    {
      key: 'ctx', title: 'Sales Context',
      fields: [
        { label: 'Salesperson', value: '—', provenance: 'Master Data gap — see docs' },
        { label: 'Price List', value: '—', provenance: 'Master Data gap — see docs' },
        { label: 'Project / Cost Center', value: '—', provenance: 'Dimensions — Phase 2 (PXL-DA-017)' },
        { label: 'Source Sales Order', value: '—', provenance: 'Conversion flow not yet linked' },
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
  const lineColumns: LineColumn<LineRow>[] = [
    { key: 'no', header: '#', group: 'system', render: l => <span className="text-gray-400">{l.line_number}</span> },
    { key: 'desc', header: 'Description', group: 'business', render: l => <span className="text-gray-900">{l.description}</span>, footer: 'Totals' },
    { key: 'qty', header: 'Qty', group: 'business', align: 'right', render: l => <span className="font-mono tabular-nums text-gray-700">{num(l.quantity)}</span> },
    { key: 'price', header: 'Unit Price', group: 'business', align: 'right', render: l => <AmountCell amount={num(l.unit_price)} /> },
    { key: 'disc', header: 'Discount', group: 'business', align: 'right', render: l => <AmountCell amount={num(l.discount_amount)} /> },
    { key: 'net', header: 'Net of VAT', group: 'business', align: 'right', render: l => <AmountCell amount={num(l.net_amount)} />, footer: <AmountCell amount={netOfVat} /> },
    { key: 'vat', header: 'VAT', group: 'business', align: 'right', render: l => <AmountCell amount={num(l.vat_amount)} />, footer: <AmountCell amount={num(si.total_vat_amount)} /> },
    { key: 'total', header: 'Total', group: 'business', align: 'right', render: l => <span className="font-semibold"><AmountCell amount={num(l.total_amount)} /></span>, footer: <AmountCell amount={num(si.total_amount)} /> },
    { key: 'acct', header: 'Revenue Acct', group: 'accounting', render: l => <span className="font-mono text-gray-600">{accountLabel(l.revenue_account_id)}</span> },
  ]
  const selectedLine = lines.find(l => l.id === selectedLineId) ?? null
  const lineDetailSections: DetailSection[] = selectedLine ? [
    { key: 'gen', title: 'General', fields: [
      { label: 'Line', value: selectedLine.line_number },
      { label: 'Description', value: selectedLine.description, wide: true },
      { label: 'Quantity', value: num(selectedLine.quantity) },
    ] },
    { key: 'price', title: 'Pricing', fields: [
      { label: 'Unit Price', value: <AmountCell amount={num(selectedLine.unit_price)} /> },
      { label: 'Discount %', value: `${num(selectedLine.discount_percent)}%` },
      { label: 'Discount Amount', value: <AmountCell amount={num(selectedLine.discount_amount)} /> },
      { label: 'Net of VAT', value: <AmountCell amount={num(selectedLine.net_amount)} /> },
    ] },
    { key: 'tax', title: 'Tax & Account', fields: [
      { label: 'VAT Amount', value: <AmountCell amount={num(selectedLine.vat_amount)} /> },
      { label: 'Line Total', value: <AmountCell amount={num(selectedLine.total_amount)} /> },
      { label: 'Revenue Account', value: accountLabel(selectedLine.revenue_account_id) },
    ] },
  ] : []
  const linesTab = (
    <div>
      <LineGrid columns={lineColumns} rows={lines} getRowKey={l => l.id} emptyLabel="No lines on this invoice."
        onRowClick={l => setSelectedLineId(prev => prev === l.id ? null : l.id)} selectedKey={selectedLineId ?? undefined} />
      {selectedLine && (
        <LineDetailPanel title={`Line ${selectedLine.line_number} — ${selectedLine.description}`} sections={lineDetailSections} onClose={() => setSelectedLineId(null)} />
      )}
      <p className="text-[11px] text-gray-400 mt-2">{lines.length} line{lines.length !== 1 ? 's' : ''} · click a row for detail. Accountant/auditor column profiles (ATC, dimensions, source refs) arrive with the editable grid.</p>
    </div>
  )

  // ── Financial Summary (full, §10) ───────────────────────────
  const summaryFull: SummaryGroup[] = [
    { key: 'main', rows: [
      { key: 'sub', label: 'Subtotal before discount', value: subtotal },
      ...(discounts > 0 ? [{ key: 'disc', label: 'Less: line discounts', value: discounts, variant: 'muted' as const, paren: true }] : []),
      { key: 'net', label: 'Net of VAT / VAT base', value: netOfVat },
      ...(num(si.total_zero_rated_amount) > 0 ? [{ key: 'zero', label: 'Zero-rated', value: num(si.total_zero_rated_amount), variant: 'muted' as const }] : []),
      ...(num(si.total_exempt_amount) > 0 ? [{ key: 'exempt', label: 'Exempt', value: num(si.total_exempt_amount), variant: 'muted' as const }] : []),
      { key: 'vat', label: 'Output VAT', value: num(si.total_vat_amount) },
      { key: 'gross', label: 'Gross invoice amount', value: num(si.total_amount), variant: 'total' as const, divider: true },
    ] },
    ...(cwt > 0 ? [{ key: 'cwt', tone: 'info' as const, rows: [
      { key: 'less-cwt', label: 'Less: expected customer CWT', value: cwt, variant: 'muted' as const, paren: true },
      { key: 'netcoll', label: 'Net amount collectible', value: expectedNet, variant: 'total' as const },
    ], note: 'CWT is informational — not a discount. Settled when the customer remits BIR Form 2307 against the Official Receipt.' }] : []),
    ...(si.status === 'posted' ? [{ key: 'coll', rows: [
      { key: 'paid', label: 'Amount collected (cash + CWT)', value: collection.paid + collection.cwt, variant: 'muted' as const },
      { key: 'bal', label: 'Balance due', value: collection.balance, variant: 'total' as const, divider: true },
    ] }] : []),
  ]
  const financialTab = <FinancialSummaryPanel title="Financial Summary" groups={summaryFull} />

  const glTab = <GLImpactPanel companyId={companyId} sourceDocType="SI" sourceDocId={si.id} previewRows={[]} />
  const taxTab = <TaxImpactPanel sourceDocType="SI" sourceDocId={si.id} fallbackLabel="Output VAT"
    fallbackBase={num(si.total_taxable_amount)} fallbackRate={12} fallbackAmount={num(si.total_vat_amount)} />

  // ── Posting Validation ──────────────────────────────────────
  const postable = si.status === 'draft' || si.status === 'approved'
  const docChecks: ValidationCheck[] = [
    { key: 'number', label: 'Document number assigned', state: si.si_number ? 'ok' : 'blocked' },
    { key: 'lines', label: 'At least one line item', state: lines.length > 0 ? 'ok' : 'blocked' },
    { key: 'cust', label: 'Customer active with tax profile', state: customer ? 'ok' : 'info' },
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

  // ── Approval tab ────────────────────────────────────────────
  const approvalTab = approval ? (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <tbody className="divide-y divide-gray-100">
          {[
            ['Status', <StatusBadge key="s" status={approval.status === 'approved' ? 'approved' : approval.status === 'rejected' ? 'error' : 'pending'} label={approval.status} />],
            ['Required approver', approval.required_approver_type ?? '—'],
            ['Decided by', approval.actual_approver_id ?? 'Pending'],
            ['Submitted', formatDateTime(approval.created_at)],
            ['Approved', formatDateTime(approval.approved_at)],
            ['Comments', approval.decision_comments ?? '—'],
          ].map(([k, v], i) => (
            <tr key={i}><td className="px-3 py-2 text-xs text-gray-400 w-48">{k}</td><td className="px-3 py-2 text-xs text-gray-800">{v}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  ) : (
    <EmptyState title="No approval workflow configured"
      description="Sales Invoice has no approval instance for this company. Posting authority is gated by role and segregation-of-duties (DEC-009 / DEC-010): the poster must differ from the creator where a workflow is configured." />
  )

  // ── Audit Trail ─────────────────────────────────────────────
  const auditFacts = [
    { label: 'Created', value: formatDateTime(si.created_at) },
    { label: 'Last edited', value: formatDateTime(si.updated_at) },
    { label: 'Approved', value: formatDateTime(si.approved_at) },
    { label: 'Posted', value: formatDateTime(si.posted_at) },
    { label: 'Lock status', value: lockLabel },
  ]
  const auditTab = (
    <div className="space-y-3">
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
        {auditFacts.map(f => (
          <div key={f.label}><div className="text-[10px] uppercase tracking-wide text-gray-400 mb-1">{f.label}</div><div className="text-xs font-medium text-gray-700">{f.value}</div></div>
        ))}
      </div>
      <AuditTrailSection tableName="sales_invoices" recordId={si.id} />
    </div>
  )

  // ── Activity Timeline (lifecycle facts; semantic events pending PXL-DA-016) ──
  const timelineEvents = [
    { label: 'Created', at: si.created_at },
    ...(si.approved_at ? [{ label: 'Approved', at: si.approved_at }] : []),
    ...(si.posted_at ? [{ label: 'Posted', at: si.posted_at }] : []),
    ...(collection.receiptCount > 0 ? [{ label: `Collection applied (${collection.receiptCount} receipt${collection.receiptCount !== 1 ? 's' : ''})`, at: null }] : []),
    ...(si.status === 'cancelled' ? [{ label: 'Voided', at: si.updated_at }] : []),
  ]
  const timelineTab = (
    <ol className="relative border-l border-gray-200 ml-2 space-y-4">
      {timelineEvents.map((e, i) => (
        <li key={i} className="ml-4">
          <span className="absolute -left-1.5 w-3 h-3 rounded-full bg-gray-300 border-2 border-white" />
          <div className="text-sm text-gray-800">{e.label}</div>
          <div className="text-xs text-gray-400">{e.at ? formatDateTime(e.at) : '—'}</div>
        </li>
      ))}
      <li className="ml-4 text-[11px] text-gray-400">Semantic event stream (edited/printed/emailed) arrives with PXL-DA-016 transaction_events.</li>
    </ol>
  )

  // ── Notes ───────────────────────────────────────────────────
  const notesTab = (
    <div className="space-y-3 text-sm">
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-widest text-gray-400 mb-1">Customer-visible Memo</div>
        <div className="text-gray-700 whitespace-pre-wrap">{si.memo || <span className="text-gray-400">No memo.</span>}</div>
      </div>
      <p className="text-[11px] text-gray-400 pt-2 border-t border-gray-100">Internal / reviewer / posting note threads are not stored yet — a single memo field exists today. Threaded notes are a Phase-2 enhancement.</p>
    </div>
  )

  // ── Attachments (no storage integration yet) ────────────────
  const attachmentsTab = (
    <EmptyState title="No attachments"
      description="Document attachment storage is not yet integrated for Sales Invoices (only the CAS attachment register exists today). Supplier-invoice scans / supporting files are a Phase-2 capability." />
  )

  // ── System ──────────────────────────────────────────────────
  const systemTab = (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-xs">
      {[
        ['Record ID', si.id], ['Company ID', si.company_id], ['Branch ID', si.branch_id],
        ['Customer ID', si.customer_id], ['Source Type', 'SI'], ['Created Source', 'Manual'],
        ['Posting RPC', 'fn_post_sales_invoice'], ['Void RPC', 'fn_void_sales_invoice'],
        ['Tax Ledger', 'tax_detail_entries (source_doc_type=SI)'], ['Lock State', lockLabel],
      ].map(([k, v]) => (
        <div key={k} className="flex justify-between gap-4 py-1 border-b border-gray-50">
          <span className="text-gray-400">{k}</span><span className="font-mono text-gray-600 truncate" title={String(v)}>{v}</span>
        </div>
      ))}
    </div>
  )

  const tabs: DocumentTab[] = [
    { key: 'lines', label: 'Lines', badge: lines.length || undefined, content: linesTab },
    { key: 'financial', label: 'Financial Summary', content: financialTab },
    { key: 'gl', label: 'GL Impact', content: glTab },
    { key: 'tax', label: 'Tax Impact', content: taxTab },
    { key: 'validation', label: 'Posting Validation', content: validationTab },
    { key: 'approval', label: 'Approval', content: approvalTab },
    { key: 'audit', label: 'Audit Trail', content: auditTab },
    { key: 'related', label: 'Related Documents', content: <RelatedDocumentsTab rows={relatedRows} /> },
    { key: 'attachments', label: 'Attachments', content: attachmentsTab },
    { key: 'timeline', label: 'Activity Timeline', content: timelineTab },
    { key: 'notes', label: 'Notes', content: notesTab },
    { key: 'system', label: 'System', content: systemTab },
  ]

  // ── Right sidebar (§21) ─────────────────────────────────────
  const availableCredit = customer?.credit_limit != null ? num(customer.credit_limit) - collection.balance : null
  const rightRail = (
    <>
      <SidebarCard title="Financial Summary">
        <CardRow label="Net of VAT" value={<AmountCell amount={netOfVat} />} />
        <CardRow label="Output VAT" value={<AmountCell amount={num(si.total_vat_amount)} />} />
        <CardRow label="Gross Invoice" value={<AmountCell amount={num(si.total_amount)} />} strong />
        {cwt > 0 && <CardRow label="Expected CWT" value={<AmountCell amount={cwt} />} muted paren />}
        {cwt > 0 && <CardRow label="Net Collectible" value={<AmountCell amount={expectedNet} />} />}
        {si.status === 'posted' && <CardRow label="Collected" value={<AmountCell amount={collection.paid + collection.cwt} />} muted />}
        {si.status === 'posted' && <CardRow label="Balance Due" value={<AmountCell amount={collection.balance} />} strong />}
      </SidebarCard>

      <SidebarCard title="Customer Snapshot">
        <div className="text-sm font-medium text-gray-900">{si.customer_name_snapshot}</div>
        <div className="text-xs font-mono text-gray-500 mb-2">TIN {si.customer_tin_snapshot || '—'}</div>
        <CardRow label="VAT Classification" value={customer ? (TAX_TYPE_LABEL[customer.default_tax_type] ?? customer.default_tax_type) : '—'} muted />
        <CardRow label="Withholding" value={customer?.is_withholding_agent ? 'Agent' : 'No'} muted />
        <CardRow label="Payment Terms" value={customer ? termLabel(customer.default_terms_id) : termLabel(si.payment_terms_id)} muted />
        <CardRow label="Credit Limit" value={customer?.credit_limit != null ? <AmountCell amount={num(customer.credit_limit)} /> : '—'} muted />
        {si.status === 'posted' && <CardRow label="Available Credit" value={availableCredit != null ? <AmountCell amount={availableCredit} /> : '—'} muted />}
        {customer?.contact_person && <div className="text-[11px] text-gray-400 mt-1">Contact: {customer.contact_person}</div>}
      </SidebarCard>

      {cwt > 0 && (
        <SidebarCard title="Tax Summary">
          <CardRow label="Output VAT" value={<AmountCell amount={num(si.total_vat_amount)} />} />
          <CardRow label="Expected CWT" value={<AmountCell amount={cwt} />} muted />
          <p className="text-[10px] text-gray-400 mt-1">VAT-only in Tax Impact; EWT/CWT base pending PXL-AUD-031/032/033.</p>
        </SidebarCard>
      )}

      <SidebarCard title="Posting Validation">
        {si.status === 'posted'
          ? <div className="text-xs text-blue-700">Posted Successfully · Frozen</div>
          : readiness.loading
            ? <div className="text-xs text-gray-400">Checking…</div>
            : readiness.blockers.length === 0
              ? <div className="text-xs text-green-700">Ready to post</div>
              : <div className="text-xs text-red-700">{readiness.blockers.length} blocker{readiness.blockers.length !== 1 ? 's' : ''}</div>}
      </SidebarCard>

      <SidebarCard title="Quick Actions">
        <div className="flex flex-col gap-1.5">
          {si.status === 'posted' && <button onClick={() => navigate('/receipts')} className="text-left text-xs text-gray-700 hover:text-gray-900 hover:underline">→ Create Receipt</button>}
          {si.status === 'posted' && <button onClick={() => navigate('/credit-memos')} className="text-left text-xs text-gray-700 hover:text-gray-900 hover:underline">→ Create Credit Memo</button>}
          <button onClick={() => window.print()} className="text-left text-xs text-gray-700 hover:text-gray-900 hover:underline">→ Print</button>
          <button onClick={() => navigate(`/accounting-trace?sourceType=SI&sourceId=${si.id}`)} className="text-left text-xs text-gray-700 hover:text-gray-900 hover:underline">→ Open Full Accounting Trace</button>
        </div>
      </SidebarCard>

      <SidebarCard title="Audit Summary">
        <CardRow label="Created" value={<span className="text-[11px]">{si.created_at ? new Date(si.created_at).toLocaleDateString('en-PH') : '—'}</span>} muted />
        <CardRow label="Posted" value={<span className="text-[11px]">{si.posted_at ? new Date(si.posted_at).toLocaleDateString('en-PH') : '—'}</span>} muted />
        <CardRow label="Lock" value={lockLabel} muted />
      </SidebarCard>
    </>
  )

  return (
    <>
      {actionError && <div className="mb-3 border border-red-200 bg-red-50 rounded-md px-4 py-2 text-sm text-red-700">{actionError}</div>}
      <DocumentLayout
        title="Sales Invoice"
        documentNo={si.si_number}
        status={statusToShared[si.status]}
        statusLabel={si.status.charAt(0).toUpperCase() + si.status.slice(1)}
        meta={[
          { label: 'Date', value: <DateCell date={si.date} /> },
          { label: 'Branch', value: branchName || '—' },
          { label: 'Currency', value: si.currency_code },
          { label: 'Posting', value: <StatusBadge status={si.status === 'posted' ? 'posted' : si.status === 'cancelled' ? 'error' : 'draft'} label={postingLabel} /> },
          ...(collection.status ? [{ label: 'Collection', value: <StatusBadge status={collection.status === 'Paid' ? 'success' : collection.status === 'Partially Paid' ? 'pending' : 'open'} label={collection.status} /> }] : []),
          { label: 'Lock', value: <StatusBadge status={si.status === 'draft' ? 'draft' : 'locked'} label={lockLabel} /> },
        ]}
        workflow={workflow}
        actions={actions}
        primary={primaryInfo}
        tabs={tabs}
        rightRail={rightRail}
        onBack={backToList}
      />

      {showVoid && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => setShowVoid(false)} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
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
