import type { ReactNode } from 'react'
import DocumentLayout, {
  type DocumentIdentity,
  type DocumentMetaField,
  type DocumentMetric,
  type DocumentTab,
  type ToolbarAction,
  type WorkflowStep,
} from './DocumentLayout'
import {
  TransactionEmptyState,
  TransactionInfoCard,
  TransactionInfoCards,
  type TransactionFact,
} from './TransactionPrimitives'
import type { TransactionWorkspaceFamily } from '@/lib/transactionWorkspace'

const STANDARD_TRANSACTION_TAB_ORDER = [
  ['lines', 'Lines'],
  ['financial', 'Financial'],
  ['gl', 'GL Impact'],
  ['tax', 'Tax Impact'],
  ['validation', 'Validation'],
  ['workflow', 'Workflow'],
  ['approval', 'Approval'],
  ['audit', 'Audit'],
  ['related', 'Related Docs'],
  ['party', 'Related Party'],
  ['attachments', 'Attachments'],
  ['activity', 'Activity'],
  ['notes', 'Notes'],
  ['system', 'System'],
] as const

export type StandardTransactionTabKey = typeof STANDARD_TRANSACTION_TAB_ORDER[number][0]

export type TransactionWorkspaceCard = {
  title: string
  facts?: TransactionFact[]
  content?: ReactNode
}

export type TransactionSidebarPanel = {
  key: string
  title: string
  content: ReactNode
}

type TransactionWorkspaceProps = {
  title: string
  documentNo?: string | null
  status?: string
  statusLabel?: string
  family: TransactionWorkspaceFamily
  identity?: DocumentIdentity
  metrics?: DocumentMetric[]
  meta?: DocumentMetaField[]
  actions?: ToolbarAction[]
  workflow: { steps: WorkflowStep[]; currentKey: string }
  cards?: TransactionWorkspaceCard[]
  /** Shared three-card band supplied by a legacy source-backed renderer. */
  primary?: ReactNode
  tabContent: Partial<Record<StandardTransactionTabKey, ReactNode>>
  tabBadges?: Partial<Record<StandardTransactionTabKey, ReactNode>>
  emptyTabMessages?: Partial<Record<StandardTransactionTabKey, string>>
  sidebarPanels?: TransactionSidebarPanel[]
  footer?: ReactNode
  onBack?: () => void
  backLabel?: string
  activeTabKey?: string
  onTabChange?: (key: string) => void
}

const defaultEmptyMessage = (title: string, label: string) =>
  `${label} information is not available for this ${title.toLowerCase()}.`

export function TransactionSidebarPanels({
  title,
  status,
  statusLabel,
  metrics,
  actions,
  panels,
}: {
  title: string
  status?: string
  statusLabel?: string
  metrics: DocumentMetric[]
  actions: ToolbarAction[]
  panels?: TransactionSidebarPanel[]
}) {
  const visibleActions = actions.filter(action => !action.hidden)
  const resolvedPanels = panels && panels.length > 0
    ? panels
    : [
        {
          key: 'summary',
          title: 'Summary',
          content: metrics.length > 0 ? (
            <dl className="space-y-2">
              {metrics.map(metric => (
                <div key={metric.label} className="flex items-baseline justify-between gap-3 border-b border-[var(--pxl-border-soft)] pb-2 last:border-0 last:pb-0">
                  <dt className="pxl-field-label">{metric.label}</dt>
                  <dd className={`font-mono text-xs tabular-nums text-right ${metric.emphasis ? 'font-bold text-gray-900' : 'font-semibold text-gray-700'}`}>
                    {metric.value}
                  </dd>
                </div>
              ))}
            </dl>
          ) : <p className="pxl-caption">No monetary summary applies.</p>,
        },
        {
          key: 'status',
          title: 'Status',
          content: (
            <dl className="space-y-2">
              <div className="flex items-center justify-between gap-3">
                <dt className="pxl-field-label">Lifecycle</dt>
                <dd className="text-xs font-semibold text-gray-800">{statusLabel || status || 'Draft'}</dd>
              </div>
              <div className="flex items-center justify-between gap-3">
                <dt className="pxl-field-label">Workspace</dt>
                <dd className="text-xs text-gray-600">{title}</dd>
              </div>
            </dl>
          ),
        },
      ]

  return (
    <div className="space-y-4">
      {resolvedPanels.map(panel => (
        <section key={panel.key} className="border-b border-[var(--pxl-border-medium)] pb-4 last:border-0 last:pb-0">
          <h2 className="pxl-section-title mb-2">{panel.title}</h2>
          {panel.content}
        </section>
      ))}
      <section className="border-t border-[var(--pxl-border-medium)] pt-4">
        <h2 className="pxl-section-title mb-2">Quick Actions</h2>
        {visibleActions.length > 0 ? (
          <div className="grid gap-1.5">
            {visibleActions.slice(0, 5).map(action => (
              <button
                key={action.key}
                type="button"
                onClick={action.onClick}
                disabled={action.disabled}
                title={action.title}
                className={`pxl-button justify-start text-left ${action.variant === 'danger' ? 'pxl-button--danger' : 'pxl-button--neutral'}`}>
                {action.label}
              </button>
            ))}
          </div>
        ) : <p className="pxl-caption">No actions are available in the current status.</p>}
      </section>
    </div>
  )
}

/**
 * Canonical PXL transaction workspace.
 *
 * The shell is deliberately strict: all business transactions keep the same
 * hierarchy and tab positions. Domain pages supply real content; unavailable
 * capabilities remain visible with an explicit empty state so navigation does
 * not move between transaction types.
 */
export function TransactionWorkspace({
  title,
  documentNo,
  status,
  statusLabel,
  family,
  identity,
  metrics = [],
  meta = [],
  actions = [],
  workflow,
  cards = [],
  primary: suppliedPrimary,
  tabContent,
  tabBadges = {},
  emptyTabMessages = {},
  sidebarPanels,
  footer,
  onBack,
  backLabel,
  activeTabKey,
  onTabChange,
}: TransactionWorkspaceProps) {
  const normalizedCards = [...cards]
  if (!suppliedPrimary) {
    while (normalizedCards.length < 3) {
      normalizedCards.push({
        title: normalizedCards.length === 0 ? 'Document Information' : normalizedCards.length === 1 ? 'Related Party' : 'Transaction Context',
        content: <TransactionEmptyState>No additional information applies.</TransactionEmptyState>,
      })
    }
  }

  const tabs: DocumentTab[] = STANDARD_TRANSACTION_TAB_ORDER.map(([key, label]) => ({
    key,
    label,
    badge: tabBadges[key],
    content: tabContent[key] ?? (
      <TransactionEmptyState>{emptyTabMessages[key] || defaultEmptyMessage(title, label)}</TransactionEmptyState>
    ),
  }))

  const primary = suppliedPrimary ?? (
    <TransactionInfoCards>
      {normalizedCards.slice(0, 3).map((card, index) => (
        <TransactionInfoCard key={`${card.title}-${index}`} title={card.title} facts={card.facts}>
          {card.content}
        </TransactionInfoCard>
      ))}
    </TransactionInfoCards>
  )

  return (
    <DocumentLayout
      title={title}
      documentNo={documentNo}
      status={status}
      statusLabel={statusLabel}
      visualFamily={family}
      identity={identity}
      metrics={metrics}
      meta={meta}
      actions={actions}
      workflow={workflow}
      primary={primary}
      tabs={tabs}
      sidebar={(
        <TransactionSidebarPanels
          title={title}
          status={status}
          statusLabel={statusLabel}
          metrics={metrics}
          actions={actions}
          panels={sidebarPanels}
        />
      )}
      footer={footer}
      onBack={onBack}
      backLabel={backLabel}
      activeTabKey={activeTabKey}
      onTabChange={onTabChange}
    />
  )
}

export default TransactionWorkspace
