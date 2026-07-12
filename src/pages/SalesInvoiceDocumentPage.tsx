import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { DocumentLayout, type DocumentTab, type ToolbarAction } from '@/components/document/DocumentLayout'
import { FinancialSummaryPanel, type SummaryGroup } from '@/components/document/FinancialSummaryPanel'
import { PostingValidationPanel, readinessToChecks, type ValidationCheck } from '@/components/document/PostingValidationPanel'
import { LineGrid, type LineColumn } from '@/components/document/LineGrid'
import { TaxImpactPanel } from '@/components/document/TaxImpactPanel'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { AuditTrailSection, AmountCell, DateCell, EmptyState } from '@/components/ui/shared'

// Stable identity so the readiness effect doesn't re-run each render.
const SI_REQUIRED_CONFIG: ConfigField[] = ['ar_account_id', 'vat_payable_account_id']

// ─────────────────────────────────────────────────────────────
// Sales Invoice — document-of-record view (Standard Transaction
// Workspace pilot, DEC-013/DEC-015). Deep-linkable read-only page
// (UI Principle 38) rendered through DocumentLayout. Reuses the
// authoritative GLImpactPanel and AuditTrailSection; forks nothing.
// Create/edit still run through the list modal (adopt-on-touch).
// ─────────────────────────────────────────────────────────────

type SIStatus = 'draft' | 'approved' | 'posted' | 'cancelled'

type SIRow = {
  id: string; company_id: string; branch_id: string
  si_number: string; date: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  customer_address_snapshot: string
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
  id: string; line_number: number; description: string
  quantity: number; unit_price: number; discount_amount: number
  net_amount: number; vat_amount: number; total_amount: number
  revenue_account_id: string | null
}

type AccountRef = { code: string; name: string }

const statusToShared: Record<SIStatus, string> = {
  draft: 'draft', approved: 'approved', posted: 'posted', cancelled: 'error',
}

const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'

const num = (v: unknown) => Number(v ?? 0)

export default function SalesInvoiceDocumentPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { companyId } = useAppCtx()

  const [si, setSi] = useState<SIRow | null>(null)
  const [lines, setLines] = useState<LineRow[]>([])
  const [accounts, setAccounts] = useState<Record<string, AccountRef>>({})
  const [loading, setLoading] = useState(true)
  const [notFound, setNotFound] = useState(false)

  const load = useCallback(async () => {
    if (!id) return
    setLoading(true); setNotFound(false)
    const [{ data: head }, { data: lineRows }] = await Promise.all([
      supabase.from('sales_invoices').select('*').eq('id', id).maybeSingle(),
      supabase.from('sales_invoice_lines').select('*').eq('sales_invoice_id', id).order('line_number'),
    ])
    if (!head) { setNotFound(true); setLoading(false); return }
    setSi(head as unknown as SIRow)
    setLines((lineRows ?? []) as unknown as LineRow[])
    // Account names for the accounting column group (§5) — provenance display.
    if (head.company_id) {
      const { data: acc } = await supabase
        .from('chart_of_accounts')
        .select('id,account_code,account_name')
        .eq('company_id', head.company_id)
      const map: Record<string, AccountRef> = {}
      for (const a of acc ?? []) map[a.id] = { code: a.account_code, name: a.account_name }
      setAccounts(map)
    }
    setLoading(false)
  }, [id])

  useEffect(() => { load() }, [load])

  // Live setup preflight — mirrors the server checks the post RPC runs.
  // Called unconditionally (hooks rule); surfaced only for postable docs.
  const readiness = useTransactionReadiness({
    companyId,
    branchId: si?.branch_id ?? '',
    documentCode: 'SI',
    postingDate: si?.date ?? '',
    requiredConfig: SI_REQUIRED_CONFIG,
  })

  const backToList = () => navigate('/sales-invoices')

  if (loading) {
    return <div className="py-16 text-center text-sm text-gray-400">Loading Sales Invoice…</div>
  }
  if (notFound || !si) {
    return (
      <div className="py-10">
        <EmptyState
          title="Sales Invoice not found"
          description="It may have been removed, or belongs to a different company than the one currently selected."
          action={<button onClick={backToList} className="px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800">← Back to Sales Invoices</button>}
        />
      </div>
    )
  }

  const netOfVat = num(si.total_taxable_amount) + num(si.total_zero_rated_amount) + num(si.total_exempt_amount)
  const cwt = num(si.cwt_amount_expected)
  const expectedNet = num(si.total_amount) - cwt

  // Workflow strip
  const baseSteps = [
    { key: 'draft', label: 'Draft' },
    { key: 'approved', label: 'Approved' },
    { key: 'posted', label: 'Posted' },
  ]
  const workflow = si.status === 'cancelled'
    ? { steps: [...baseSteps, { key: 'cancelled', label: 'Voided' }], currentKey: 'cancelled' }
    : { steps: baseSteps, currentKey: si.status }

  // Toolbar (read-only document of record for this pilot slice)
  const actions: ToolbarAction[] = [
    ...(si.status === 'draft'
      ? [{ key: 'edit', label: 'Edit in list', variant: 'primary' as const, onClick: backToList, title: 'Draft editing runs in the list editor for now' }]
      : []),
    { key: 'print', label: 'Print', onClick: () => window.print() },
    { key: 'refresh', label: 'Refresh', group: 'more' as const, onClick: load },
    { key: 'trace', label: 'Open accounting trace', group: 'more' as const, onClick: () => navigate(`/accounting-trace?sourceType=SI&sourceId=${si.id}`) },
  ]

  // ── Tabs ────────────────────────────────────────────────────
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
  const linesTab = (
    <LineGrid columns={lineColumns} rows={lines} getRowKey={l => l.id} emptyLabel="No lines on this invoice." />
  )

  const glTab = (
    <GLImpactPanel companyId={companyId} sourceDocType="SI" sourceDocId={si.id} previewRows={[]} />
  )

  const taxTab = (
    <TaxImpactPanel
      sourceDocType="SI"
      sourceDocId={si.id}
      fallbackLabel="Output VAT"
      fallbackBase={num(si.total_taxable_amount)}
      fallbackRate={12}
      fallbackAmount={num(si.total_vat_amount)}
    />
  )

  const postable = si.status === 'draft' || si.status === 'approved'
  const docChecks: ValidationCheck[] = [
    { key: 'number', label: 'Document number assigned', state: si.si_number ? 'ok' : 'blocked' },
    { key: 'lines', label: 'At least one line item', state: lines.length > 0 ? 'ok' : 'blocked' },
  ]
  if (si.status === 'posted') {
    docChecks.push({ key: 'posted', label: 'Posted to the general ledger', state: 'ok' })
    docChecks.push({ key: 'frozen', label: 'Frozen by lifecycle controls — correct via void/reverse only', state: 'ok' })
  } else if (si.status === 'cancelled') {
    docChecks.push({ key: 'void', label: 'Voided — SI number retired per BIR (never reused)', state: 'info' })
  }
  const validationChecks: ValidationCheck[] = postable ? [...readinessToChecks(readiness), ...docChecks] : docChecks
  const validationTab = (
    <PostingValidationPanel
      checks={validationChecks}
      title="Posting Validation"
      footnote={postable
        ? 'Live preflight — each check mirrors a server-side validation the post RPC enforces (blueprint §11). Approval segregation-of-duties surfaces here once multi-step routing lands.'
        : 'Derived from the saved document. The setup preflight above applies to postable (draft/approved) invoices.'}
    />
  )

  const auditFacts = [
    { label: 'Created', value: formatDateTime(si.created_at) },
    { label: 'Last edited', value: formatDateTime(si.updated_at) },
    { label: 'Approved', value: formatDateTime(si.approved_at) },
    { label: 'Posted', value: formatDateTime(si.posted_at) },
    { label: 'Lock status', value: si.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ]
  const auditTab = (
    <div className="space-y-3">
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
        {auditFacts.map(f => (
          <div key={f.label}>
            <div className="text-[10px] uppercase tracking-wide text-gray-400 mb-1">{f.label}</div>
            <div className="text-xs font-medium text-gray-700">{f.value}</div>
          </div>
        ))}
      </div>
      <AuditTrailSection tableName="sales_invoices" recordId={si.id} />
    </div>
  )

  const relatedTab = (
    <div className="text-sm text-gray-600 space-y-3">
      <p>Bidirectional document chain (Quotation → SO → DR → SI → OR → JE) renders here once the RelatedDocumentsTab lands (blueprint §12). For now, follow the posted journal entry:</p>
      <button onClick={() => navigate(`/accounting-trace?sourceType=SI&sourceId=${si.id}`)}
        className="px-3 py-1.5 rounded-md text-sm font-medium border border-gray-300 text-gray-700 hover:bg-gray-50">
        Open accounting trace →
      </button>
    </div>
  )

  const tabs: DocumentTab[] = [
    { key: 'lines', label: 'Lines', badge: lines.length || undefined, content: linesTab },
    { key: 'gl', label: 'GL Impact', content: glTab },
    { key: 'tax', label: 'Tax Impact', content: taxTab },
    { key: 'validation', label: 'Posting Validation', content: validationTab },
    { key: 'audit', label: 'Audit Trail', content: auditTab },
    { key: 'related', label: 'Related', content: relatedTab },
  ]

  // ── Right rail: Financial Summary (§8 SI contract) ──────────
  const summaryGroups: SummaryGroup[] = [
    {
      key: 'main',
      rows: [
        { key: 'net', label: 'Net of VAT', value: netOfVat },
        ...(num(si.total_zero_rated_amount) > 0 ? [{ key: 'zero', label: 'Zero-rated', value: num(si.total_zero_rated_amount), variant: 'muted' as const }] : []),
        ...(num(si.total_exempt_amount) > 0 ? [{ key: 'exempt', label: 'Exempt', value: num(si.total_exempt_amount), variant: 'muted' as const }] : []),
        { key: 'vat', label: 'Output VAT', value: num(si.total_vat_amount) },
        { key: 'total', label: 'Invoice Total', value: num(si.total_amount), variant: 'total' as const, divider: true },
      ],
    },
    ...(cwt > 0 ? [{
      key: 'cwt',
      tone: 'info' as const,
      rows: [
        { key: 'less-cwt', label: 'Less: expected CWT', value: cwt, variant: 'muted' as const, paren: true },
        { key: 'net-coll', label: 'Expected Net Collectible', value: expectedNet, variant: 'total' as const },
      ],
      note: 'CWT is informational — collected when the customer remits BIR Form 2307 against the Official Receipt.',
    }] : []),
  ]
  const rightRail = (
    <>
      <FinancialSummaryPanel groups={summaryGroups} />
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-2">
        <div className="text-[10px] font-semibold uppercase tracking-widest text-gray-400 pb-2 border-b border-gray-100">Party</div>
        <div className="text-sm font-medium text-gray-900">{si.customer_name_snapshot}</div>
        <div className="text-xs font-mono text-gray-500">TIN {si.customer_tin_snapshot || '—'}</div>
        {si.customer_address_snapshot && <div className="text-xs text-gray-500 leading-snug">{si.customer_address_snapshot}</div>}
      </div>
    </>
  )

  return (
    <DocumentLayout
      title="Sales Invoice"
      documentNo={si.si_number}
      status={statusToShared[si.status]}
      statusLabel={si.status.charAt(0).toUpperCase() + si.status.slice(1)}
      meta={[
        { label: 'Date', value: <DateCell date={si.date} /> },
        { label: 'Due', value: si.due_date ? <DateCell date={si.due_date} /> : '—' },
        { label: 'Currency', value: si.currency_code },
        { label: 'Reference', value: si.reference || '—' },
      ]}
      workflow={workflow}
      actions={actions}
      tabs={tabs}
      rightRail={rightRail}
      onBack={backToList}
    />
  )
}
