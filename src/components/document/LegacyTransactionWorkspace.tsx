import type { ReactNode } from 'react'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { AuditTrailSection } from '@/components/ui/shared'
import { FinancialSummaryTable, MasterRecordLink, SystemMetadataPanel, TransactionEmptyState, TransactionImpactTable, type TransactionFact } from './TransactionPrimitives'
import { TransactionWorkspace } from './TransactionWorkspace'
import type { StandardTransactionTabKey, TransactionWorkspaceCard } from './TransactionWorkspace'
import type { ToolbarAction, WorkflowStep } from './DocumentLayout'
import type { TransactionWorkspaceFamily } from '@/lib/transactionWorkspace'
import type { TransactionWorkspacePattern } from '@/lib/transactionWorkspaceCoverage'

type LegacyTransactionWorkspaceProps = {
  title: string
  family: TransactionWorkspaceFamily
  pattern: TransactionWorkspacePattern
  posting: boolean
  children: ReactNode
  documentNo?: string | null
  status?: string | null
  identity?: ReactNode
  sourceDocType?: string
  sourceDocId?: string | null
  auditTable?: string
  financialFacts?: TransactionFact[]
  taxFacts?: TransactionFact[]
  contextFacts?: TransactionFact[]
  relatedFacts?: TransactionFact[]
  cards?: TransactionWorkspaceCard[]
  headerFields?: LegacyTransactionHeaderField[]
  actions?: ToolbarAction[]
  tabContent?: Partial<Record<StandardTransactionTabKey, ReactNode>>
  onBack?: () => void
  backLabel?: string
}

export type LegacyTransactionHeaderField = {
  key: string
  label: string
  content: ReactNode
  card: 0 | 1 | 2
  span?: 1 | 2
  hint?: ReactNode
}

const titleSet = (family: TransactionWorkspaceFamily, pattern: TransactionWorkspacePattern) => {
  if (pattern === 'B') return ['Document Information', 'Warehouse Context', 'Movement Context']
  if (pattern === 'C') return ['Document Information', 'Payment Information', 'Settlement Context']
  if (pattern === 'D') return ['Document Information', 'Accounting Context', 'Posting Context']
  if (family === 'purchase') return ['Document Information', 'Supplier Information', 'Purchase Context']
  if (family === 'sales') return ['Document Information', 'Customer Information', 'Sales Context']
  if (family === 'banking') return ['Document Information', 'Bank Information', 'Settlement Context']
  return ['Document Information', 'Transaction Context', 'Posting Context']
}

const workflowFor = (pattern: TransactionWorkspacePattern, posting: boolean): WorkflowStep[] => {
  if (pattern === 'B') return [{ key: 'draft', label: 'Draft' }, { key: 'approved', label: 'Approved' }, { key: 'posted', label: 'Posted / Completed' }, { key: 'cancelled', label: 'Voided' }]
  if (pattern === 'C') return [{ key: 'draft', label: 'Draft' }, { key: 'approved', label: 'Approved' }, { key: 'posted', label: 'Posted' }, { key: 'cancelled', label: 'Voided' }]
  if (pattern === 'D') return [{ key: 'draft', label: 'Draft' }, { key: 'approved', label: 'Approved' }, { key: 'posted', label: 'Posted' }, { key: 'reversed', label: 'Reversed' }]
  if (!posting || pattern === 'E') return [{ key: 'draft', label: 'Draft' }, { key: 'pending', label: 'Pending Approval' }, { key: 'approved', label: 'Approved' }, { key: 'closed', label: 'Closed / Converted' }]
  return [{ key: 'draft', label: 'Draft' }, { key: 'approved', label: 'Approved' }, { key: 'posted', label: 'Posted' }, { key: 'cancelled', label: 'Voided' }]
}

/**
 * Transitional composition used by implemented domain pages whose field and
 * action code remains page-owned. It changes their rendered information
 * architecture immediately while keeping the existing business line editor
 * mounted once inside Lines. Header fields and actions are supplied to the
 * shared cards/header rather than repeated inside the child. New pages should use
 * TransactionWorkspace directly.
 */
export function LegacyTransactionWorkspace({
  title,
  family,
  pattern,
  posting,
  children,
  documentNo,
  status,
  identity,
  sourceDocType,
  sourceDocId,
  auditTable,
  financialFacts = [],
  taxFacts = [],
  contextFacts = [],
  relatedFacts = [],
  cards,
  headerFields = [],
  actions = [],
  tabContent: suppliedTabContent = {},
  onBack,
  backLabel,
}: LegacyTransactionWorkspaceProps) {
  const resolvedStatus = (status || 'draft').toLowerCase()
  const workflow = workflowFor(pattern, posting)
  const workflowCurrent = workflow.some(step => step.key === resolvedStatus)
    ? resolvedStatus
    : resolvedStatus.includes('post') || resolvedStatus.includes('complete') || resolvedStatus.includes('receive')
      ? 'posted'
      : resolvedStatus.includes('approv')
        ? 'approved'
        : resolvedStatus.includes('cancel') || resolvedStatus.includes('void')
          ? 'cancelled'
          : 'draft'
  const cardTitles = titleSet(family, pattern)
  const resolvedCards = cards || (headerFields.length > 0
    ? cardTitles.map((cardTitle, cardIndex) => ({
        title: cardTitle,
        content: (
          <div className="grid min-w-0 grid-cols-2 gap-x-3 gap-y-2">
            {headerFields.filter(field => field.card === cardIndex).map(field => (
              <div key={field.key} className={field.span === 2 ? 'col-span-2 min-w-0' : 'min-w-0'}>
                <div className="pxl-field-label">{field.label}</div>
                <div className="mt-1 min-w-0">{field.content}</div>
                {field.hint && <div className="pxl-caption mt-0.5">{field.hint}</div>}
              </div>
            ))}
          </div>
        ),
      }))
    : cardTitles.map((cardTitle, index) => ({
        title: cardTitle,
        facts: index === 0 ? [
          { label: 'Document', value: documentNo || `Unsaved ${title}` },
          { label: 'Status', value: status || 'Draft' },
        ] : index === 1 ? (contextFacts.length > 0 ? contextFacts.slice(0, 4) : [
          { label: 'Transaction Type', value: title },
          { label: 'Details', value: 'Review transaction-specific fields in Lines' },
        ]) : (contextFacts.length > 4 ? contextFacts.slice(4, 8) : [
          { label: 'Posting Behavior', value: posting ? 'Posting and period controls remain active' : 'No direct GL posting' },
          { label: 'Lifecycle', value: status || 'Draft' },
        ]),
      })))

  return (
    <TransactionWorkspace
      title={title}
      documentNo={documentNo}
      status={resolvedStatus}
      statusLabel={status || 'Draft'}
      family={family}
      identity={{ name: identity || title, secondary: posting ? 'Posting controlled' : 'Non-posting source document' }}
      metrics={financialFacts.length > 0
        ? financialFacts.slice(0, 3).map((fact, index) => ({ label: fact.label, value: fact.value, emphasis: index === 0 }))
        : [
            { label: 'Document State', value: status || 'Draft', emphasis: true },
            { label: 'Posting', value: posting ? 'Posting controlled' : 'No direct posting' },
            { label: 'Record', value: documentNo ? 'Saved document' : 'New transaction' },
          ]}
      meta={[{ label: 'Posting', value: posting ? 'Controlled' : 'No direct posting', tone: posting ? 'info' : 'neutral' }]}
      actions={actions}
      workflow={{ steps: workflow, currentKey: workflowCurrent }}
      cards={resolvedCards}
      tabContent={{
        lines: <div className="pxl-legacy-transaction-content">{children}</div>,
        financial: financialFacts.length > 0 ? (
          <FinancialSummaryTable
            label={`${title} financial summary`}
            columns={[
              { key: 'measure', label: 'Measure', render: fact => fact.label },
              { key: 'value', label: 'Value', align: 'right', render: fact => fact.value },
              { key: 'basis', label: 'Basis', render: fact => fact.hint || 'Source-backed transaction state' },
            ]}
            rows={financialFacts}
            getRowKey={fact => fact.label}
            emptyLabel={`No financial summary applies to this ${title}.`}
          />
        ) : <TransactionEmptyState>No separate financial summary applies. Source-backed operational values remain available in Lines.</TransactionEmptyState>,
        gl: posting
          ? sourceDocType && sourceDocId
            ? <GLImpactPanel companyId={null} sourceDocType={sourceDocType} sourceDocId={sourceDocId} previewRows={[]} />
            : <TransactionEmptyState>Save or post this {title} to load an authoritative GL impact. No journal is inferred before the posting engine returns it.</TransactionEmptyState>
          : <TransactionEmptyState>{title} has no direct GL posting in its current lifecycle design.</TransactionEmptyState>,
        tax: taxFacts.length > 0 ? (
          <TransactionImpactTable
            label={`${title} tax impact`}
            columns={[
              { key: 'treatment', label: 'Tax Treatment', render: fact => fact.label },
              { key: 'value', label: 'Amount / Value', align: 'right', render: fact => fact.value },
              { key: 'basis', label: 'Basis', render: fact => fact.hint || 'Transaction tax state' },
            ]}
            rows={taxFacts}
            getRowKey={fact => fact.label}
            emptyLabel={`No tax impact applies to this ${title}.`}
          />
        ) : <TransactionEmptyState>No separate tax impact applies or is exposed by the authoritative transaction query. Tax is not inferred.</TransactionEmptyState>,
        validation: <div className="pxl-validation-message border border-blue-200 bg-blue-50 text-blue-800">Field, lifecycle, period, and posting validations remain enforced by the transaction actions in the top header.</div>,
        workflow: <ol className="grid gap-2 sm:grid-cols-4">{workflow.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === workflowCurrent ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
        approval: <TransactionEmptyState>No separate approval-history read model is exposed here. Available approval actions remain status and permission controlled in the top header.</TransactionEmptyState>,
        audit: auditTable && sourceDocId ? <AuditTrailSection tableName={auditTable} recordId={sourceDocId} /> : <TransactionEmptyState>Audit events become available after this transaction is saved and its record identifier is known.</TransactionEmptyState>,
        related: relatedFacts.length > 0 ? (
          <TransactionImpactTable
            label={`${title} related documents`}
            columns={[
              { key: 'relationship', label: 'Relationship', render: fact => fact.label },
              { key: 'document', label: 'Document', render: fact => fact.to ? <MasterRecordLink to={fact.to}>{fact.value}</MasterRecordLink> : fact.value },
              { key: 'status', label: 'Status / Trace', render: fact => fact.hint || 'Source-backed relationship' },
            ]}
            rows={relatedFacts}
            getRowKey={fact => fact.label}
            emptyLabel={`No related documents are linked to this ${title}.`}
          />
        ) : <TransactionEmptyState>No structured related-document rows are exposed by the current domain query.</TransactionEmptyState>,
        party: <TransactionEmptyState>Use the applicable customer, supplier, employee, warehouse, or account link from the information cards for source-backed related-record context.</TransactionEmptyState>,
        activity: <TransactionEmptyState>No additional activity feed is exposed by the current transaction query.</TransactionEmptyState>,
        notes: <TransactionEmptyState>No separate notes feed is exposed; document notes remain in their single source-backed card field when applicable.</TransactionEmptyState>,
        system: <SystemMetadataPanel facts={[
          { label: 'Internal ID', value: sourceDocId || 'Assigned when saved', hint: 'Transaction identity' },
          { label: 'Document Number', value: documentNo || 'Generated from number series', hint: 'Document identity' },
          { label: 'Transaction Type', value: title, hint: 'Workspace configuration' },
          { label: 'Pattern', value: pattern, hint: 'Transaction workspace classification' },
          { label: 'Posting Behavior', value: posting ? 'Posting document' : 'Non-posting document', hint: 'Accounting behavior' },
        ]} />,
        ...suppliedTabContent,
      }}
      emptyTabMessages={{ attachments: `No attachments have been added to this ${title}.` }}
      sidebarPanels={[
        ...(financialFacts.length > 0 ? [{ key: 'summary', title: pattern === 'B' ? 'Inventory' : pattern === 'D' ? 'Balance' : 'Balance', content: <dl className="space-y-2">{financialFacts.slice(0, 4).map(fact => <div key={fact.label} className="flex justify-between gap-3 text-xs"><dt>{fact.label}</dt><dd className="font-mono font-semibold text-right">{fact.value}</dd></div>)}</dl> }] : []),
        ...(taxFacts.length > 0 ? [{ key: 'tax', title: 'Tax', content: <dl className="space-y-2">{taxFacts.slice(0, 3).map(fact => <div key={fact.label} className="flex justify-between gap-3 text-xs"><dt>{fact.label}</dt><dd className="font-mono text-right">{fact.value}</dd></div>)}</dl> }] : []),
        { key: 'status', title: 'Status', content: <div className="flex items-center justify-between gap-2"><span className="pxl-caption">Lifecycle</span><span className="text-xs font-semibold">{status || 'Draft'}</span></div> },
        { key: 'posting', title: posting ? 'Posting' : 'Expected Impact', content: <div className="flex items-center justify-between gap-2"><span className="pxl-caption">Readiness</span><span className="text-xs font-semibold text-right">{posting ? 'Controlled' : 'No direct posting'}</span></div> },
      ]}
      footer={<span>{title} · {status || 'Draft'}</span>}
      onBack={onBack}
      backLabel={backLabel}
    />
  )
}

export default LegacyTransactionWorkspace
