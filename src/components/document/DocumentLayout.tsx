import { useState, useRef, useEffect, useLayoutEffect, useCallback } from 'react'
import { createPortal } from 'react-dom'
import type { TransactionWorkspaceFamily } from '@/lib/transactionWorkspace'

// ─────────────────────────────────────────────────────────────
// PXL Transaction Workspace — permanent shared shell governed by
// PXL_TRANSACTION_WORKSPACE_STANDARD.md. Pure presentational: no data
// fetching, posting, tax, lifecycle, or permission behavior.
// ─────────────────────────────────────────────────────────────

export type WorkflowStep = { key: string; label: string }

export type DocumentMetaField = {
  label: string
  value: React.ReactNode
  tone?: 'success' | 'warning' | 'error' | 'info' | 'neutral'
}

export type DocumentIdentity = {
  name: React.ReactNode
  secondary?: React.ReactNode
}

export type DocumentMetric = {
  label: string
  value: React.ReactNode
  emphasis?: boolean
}

export type ToolbarAction = {
  key: string
  label: string
  onClick: () => void
  disabled?: boolean
  /** Visual weight. Destructive actions belong under "More" with reason capture. */
  variant?: 'primary' | 'default' | 'danger'
  /** 'more' actions collapse under the More ▾ menu (fixed toolbar order, UI Principle 16). */
  group?: 'primary' | 'more'
  hidden?: boolean
  title?: string
}

type MenuPosition = {
  top: number
  left: number
  maxHeight: number
  placement: 'top' | 'bottom'
}

export type DocumentTab = {
  key: string
  label: string
  content: React.ReactNode
  hidden?: boolean
  /** Optional count/indicator rendered next to the label. */
  badge?: React.ReactNode
}

// ── WorkflowStrip ─────────────────────────────────────────────
// Visual document lifecycle (Draft → Approved → Posted → …). The
// current step is highlighted; prior steps read as completed.
export function WorkflowStrip({ steps, currentKey }: { steps: WorkflowStep[]; currentKey: string }) {
  const currentIdx = Math.max(0, steps.findIndex(s => s.key === currentKey))
  return (
    <ol className="flex items-center flex-wrap gap-1 text-xs">
      {steps.map((step, i) => {
        const state = i < currentIdx ? 'done' : i === currentIdx ? 'current' : 'upcoming'
        return (
          <li key={step.key} className="flex items-center gap-1">
            <span
              aria-current={state === 'current' ? 'step' : undefined}
              className={`pxl-workflow-step pxl-workflow-step--${state}`}>
              {step.label}
            </span>
            {i < steps.length - 1 && <span className="pxl-workflow-connector" aria-hidden>→</span>}
          </li>
        )
      })}
    </ol>
  )
}

// ── DocumentToolbar ───────────────────────────────────────────
// Fixed-order action bar; inapplicable actions are disabled, not
// hidden (UI Principle 16). Destructive/secondary actions collapse
// under a More ▾ menu.
export function TransactionActionBar({ actions, inverse = false }: { actions: ToolbarAction[]; inverse?: boolean }) {
  const [openMore, setOpenMore] = useState(false)
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  const visible = actions.filter(a => !a.hidden)
  const primaryCandidates = visible.filter(a => (a.group ?? 'primary') === 'primary')
  const explicitMore = visible.filter(a => a.group === 'more')
  const needsMore = explicitMore.length > 0 || primaryCandidates.length > 4
  const primary = needsMore ? primaryCandidates.slice(0, 3) : primaryCandidates
  const more = [...primaryCandidates.slice(primary.length), ...explicitMore]

  const updateMenuPosition = useCallback(() => {
    const trigger = triggerRef.current
    if (!trigger) return
    const margin = 8
    const width = 224
    const rect = trigger.getBoundingClientRect()
    const measuredHeight = menuRef.current?.offsetHeight
    const estimatedHeight = Math.min(360, Math.max(96, more.length * 34 + 12))
    const menuHeight = measuredHeight || estimatedHeight
    const spaceBelow = window.innerHeight - rect.bottom - margin
    const spaceAbove = rect.top - margin
    const placement: MenuPosition['placement'] = spaceBelow < menuHeight && spaceAbove > spaceBelow ? 'top' : 'bottom'
    const maxHeight = Math.max(120, placement === 'top' ? spaceAbove - 4 : spaceBelow - 4)
    const top = placement === 'top'
      ? Math.max(margin, rect.top - Math.min(menuHeight, maxHeight) - 4)
      : Math.min(window.innerHeight - margin, rect.bottom + 4)

    let left = rect.right - width
    if (left < margin) left = rect.left
    if (left + width > window.innerWidth - margin) left = window.innerWidth - width - margin
    setMenuPosition({ top, left: Math.max(margin, left), maxHeight, placement })
  }, [more.length])

  useEffect(() => {
    if (!openMore) return
    const onDoc = (e: MouseEvent) => {
      const target = e.target as Node
      if (triggerRef.current?.contains(target) || menuRef.current?.contains(target)) return
      setOpenMore(false)
    }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpenMore(false) }
    const onMove = () => updateMenuPosition()
    document.addEventListener('mousedown', onDoc)
    document.addEventListener('keydown', onKey)
    window.addEventListener('resize', onMove)
    window.addEventListener('scroll', onMove, true)
    return () => {
      document.removeEventListener('mousedown', onDoc)
      document.removeEventListener('keydown', onKey)
      window.removeEventListener('resize', onMove)
      window.removeEventListener('scroll', onMove, true)
    }
  }, [openMore, updateMenuPosition])

  useLayoutEffect(() => {
    if (!openMore) return
    updateMenuPosition()
  }, [openMore, more.length, updateMenuPosition])

  useLayoutEffect(() => {
    if (!openMore || !menuRef.current) return
    updateMenuPosition()
  }, [menuPosition?.placement, openMore, updateMenuPosition])

  const btnCls = (a: ToolbarAction) => {
    const base = 'pxl-button'
    if (inverse) {
      if (a.variant === 'primary') return `${base} bg-white text-gray-900 hover:bg-gray-100 shadow-sm`
      if (a.variant === 'danger') return `${base} border border-red-200/60 bg-red-950/20 text-red-50 hover:bg-red-950/35`
      return `${base} border border-white/30 bg-white/10 text-white hover:bg-white/20`
    }
    if (a.variant === 'primary') return `${base} pxl-button--primary`
    if (a.variant === 'danger') return `${base} pxl-button--danger`
    return `${base} pxl-button--neutral`
  }

  return (
    <div className="flex items-center gap-1.5">
      {primary.map(a => (
        <button key={a.key} onClick={a.onClick} disabled={a.disabled} title={a.title} className={btnCls(a)}>
          {a.label}
        </button>
      ))}
      {more.length > 0 && (
        <>
          <button
            ref={triggerRef}
            onClick={() => setOpenMore(o => !o)}
            aria-haspopup="menu"
            aria-expanded={openMore}
            className={`pxl-button ${inverse
              ? 'border border-white/30 bg-white/10 text-white hover:bg-white/20'
              : 'pxl-button--neutral'}`}>
            More ▾
          </button>
          {openMore && menuPosition && createPortal(
            <div
              ref={menuRef}
              role="menu"
              aria-label="More transaction actions"
              className="pxl-dialog fixed z-[9999] w-56 overflow-y-auto py-1"
              style={{
                top: menuPosition.top,
                left: menuPosition.left,
                maxHeight: menuPosition.maxHeight,
                transformOrigin: menuPosition.placement === 'top' ? 'bottom right' : 'top right',
              }}>
              {more.map(a => (
                <button
                  key={a.key}
                  role="menuitem"
                  onClick={() => { setOpenMore(false); a.onClick() }}
                  disabled={a.disabled}
                  title={a.title}
                  className={`w-full px-3 py-2 text-left text-xs disabled:cursor-not-allowed disabled:opacity-40 ${
                    a.variant === 'danger' ? 'text-red-700 hover:bg-red-50' : 'text-gray-700 hover:bg-gray-50'}`}>
                  {a.label}
                </button>
              ))}
            </div>,
            document.body,
          )}
        </>
      )}
    </div>
  )
}

const statusTone = (status?: string): DocumentMetaField['tone'] => {
  if (!status) return 'neutral'
  if (['success', 'approved', 'posted', 'paid', 'active'].includes(status)) return 'success'
  if (['pending', 'locked', 'warning'].includes(status)) return 'warning'
  if (['error', 'cancelled', 'voided', 'rejected'].includes(status)) return 'error'
  if (['open', 'info'].includes(status)) return 'info'
  return 'neutral'
}

function HeaderStateChip({ label, value, tone = 'neutral', title }: {
  label?: string
  value: React.ReactNode
  tone?: DocumentMetaField['tone']
  title?: string
}) {
  const dot =
    tone === 'success' ? 'bg-green-500' :
    tone === 'warning' ? 'bg-orange-500' :
    tone === 'error' ? 'bg-red-500' :
    tone === 'info' ? 'bg-blue-500' :
    'bg-gray-400'
  return (
    <span title={title || label} className="inline-flex items-center gap-1.5 rounded border border-gray-200 bg-white/80 px-2 py-0.5 text-[10px] font-medium text-gray-700 shadow-sm">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} aria-hidden />
      <span className="truncate">{value}</span>
    </span>
  )
}

// ── TransactionTabsBar ────────────────────────────────────────
// Compact enterprise tab bar (NetSuite / SAP B1 / Dynamics BC
// density): every tab gets an equal share of the available width and
// labels truncate before the bar can overflow. The canonical twelve-tab
// set therefore remains one line with no arrows or horizontal scrollbar.
export function TransactionTabsBar({
  tabs, activeKey, onChange,
}: {
  tabs: DocumentTab[]
  activeKey: string
  onChange: (key: string) => void
}) {
  const visible = tabs.filter(t => !t.hidden)
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([])
  const moveFocus = (index: number) => {
    if (visible.length === 0) return
    const next = (index + visible.length) % visible.length
    const key = visible[next]?.key
    if (!key) return
    onChange(key)
    tabRefs.current[next]?.focus()
  }
  return (
    <div
      className="pxl-transaction-tabs flex w-full min-w-0 items-stretch px-1"
      role="tablist">
      {visible.map((t, index) => {
        const on = t.key === activeKey
        const tabId = `transaction-tab-${t.key}`
        const panelId = `transaction-panel-${t.key}`
        return (
          <button
            key={t.key}
            ref={node => { tabRefs.current[index] = node }}
            id={tabId}
            role="tab"
            aria-selected={on}
            aria-controls={panelId}
            tabIndex={on ? 0 : -1}
            onClick={() => onChange(t.key)}
            onKeyDown={event => {
              if (event.key === 'ArrowRight') { event.preventDefault(); moveFocus(index + 1) }
              if (event.key === 'ArrowLeft') { event.preventDefault(); moveFocus(index - 1) }
              if (event.key === 'Home') { event.preventDefault(); moveFocus(0) }
              if (event.key === 'End') { event.preventDefault(); moveFocus(visible.length - 1) }
            }}
            title={t.label}
            className={`pxl-transaction-tab ${on ? 'pxl-transaction-tab--active' : 'pxl-transaction-tab--inactive'} min-w-0 flex-1 whitespace-nowrap border-b-2 px-2 py-2 leading-none transition-colors`}>
            <span className="block truncate">{t.label}</span>
            {t.badge != null && (
              <span className="sr-only"> ({t.badge})</span>
            )}
          </button>
        )
      })}
    </div>
  )
}

export function TransactionPageHeader({
  title,
  documentNo,
  status,
  statusLabel,
  identity,
  metrics = [],
  meta = [],
  actions = [],
  onBack,
  backLabel,
}: {
  title: string
  documentNo?: string | null
  status?: string
  statusLabel?: string
  identity?: DocumentIdentity
  metrics?: DocumentMetric[]
  meta?: DocumentMetaField[]
  actions?: ToolbarAction[]
  onBack?: () => void
  backLabel?: string
}) {
  return (
    <header className="pxl-transaction-header overflow-hidden rounded-lg border-b text-gray-900">
      <div className="pxl-transaction-header__content flex flex-col gap-3 px-3 py-2.5 xl:flex-row xl:items-center">
        <div className="pxl-transaction-header__identity flex min-w-0 items-start gap-4 xl:w-[40%]">
          {onBack && (
            <button onClick={onBack} className="pxl-button pxl-button--text mt-0.5 h-8 px-2" title={`Back to ${backLabel || `${title}s`}`} aria-label={`Back to ${backLabel || `${title}s`}`}>
              <span aria-hidden>←</span>
              <span className="ml-1 hidden sm:inline">{backLabel || `${title}s`}</span>
            </button>
          )}
          <div className="min-w-0">
            <div className="pxl-header-metric-label">{title}</div>
            <div className="mt-1 flex min-w-0 flex-wrap items-center gap-2.5">
              <h1 className="pxl-document-number truncate">
                {documentNo || `Unsaved ${title}`}
              </h1>
              {status && <HeaderStateChip value={statusLabel || status} tone={statusTone(status)} label="Document status" />}
              {meta.map((field, index) => <HeaderStateChip key={`${field.label}-${index}`} value={field.value} tone={field.tone} label={field.label} />)}
            </div>
            {identity && (
              <div className="mt-2 flex min-w-0 items-center gap-3">
                <span className="pxl-customer-link truncate">{identity.name}</span>
                {identity.secondary && <span className="pxl-caption truncate font-mono">{identity.secondary}</span>}
              </div>
            )}
          </div>
        </div>

        {metrics.length > 0 && (
          <dl className="pxl-transaction-header__metrics grid min-w-0 grid-cols-3 gap-3 border-y border-[var(--pxl-border-medium)] py-2 xl:flex-1 xl:border-x xl:border-y-0 xl:px-4 xl:py-0">
            {metrics.map(metric => (
              <div key={metric.label} className="min-w-0 xl:text-right">
                <dt className="pxl-header-metric-label truncate">{metric.label}</dt>
                <dd className={`mt-1 truncate font-mono tabular-nums ${metric.emphasis ? 'pxl-header-metric-value' : 'text-sm font-semibold text-gray-800'}`}>
                  {metric.value}
                </dd>
              </div>
            ))}
          </dl>
        )}

        {actions.length > 0 && <div className="pxl-transaction-header__actions shrink-0 xl:ml-auto"><TransactionActionBar actions={actions} /></div>}
      </div>
    </header>
  )
}

export function TransactionWorkflowBanner({ steps, currentKey }: { steps: WorkflowStep[]; currentKey: string }) {
  return (
    <div className="pxl-transaction-workflow pxl-transaction-card px-3 py-1.5" aria-label="Transaction workflow status">
      <WorkflowStrip steps={steps} currentKey={currentKey} />
    </div>
  )
}

// ── TransactionTabs ───────────────────────────────────────────
// Standalone bar + active content (self-managed or controlled), for
// any surface that wants tabs inline. DocumentLayout instead renders
// the bar full-width with the content below (see below).
export function TransactionTabs({
  tabs, activeKey, onChange,
}: {
  tabs: DocumentTab[]
  activeKey?: string
  onChange?: (key: string) => void
}) {
  const visible = tabs.filter(t => !t.hidden)
  const [internal, setInternal] = useState(visible[0]?.key ?? '')
  const active = activeKey ?? internal
  const setActive = (k: string) => { if (onChange) onChange(k); else setInternal(k) }
  const activeTab = visible.find(t => t.key === active) ?? visible[0]
  return (
    <div>
      <div className="border-b border-gray-200"><TransactionTabsBar tabs={tabs} activeKey={active} onChange={setActive} /></div>
      <div
        id={activeTab ? `transaction-panel-${activeTab.key}` : undefined}
        aria-labelledby={activeTab ? `transaction-tab-${activeTab.key}` : undefined}
        className="pt-4"
        role="tabpanel">
        {activeTab?.content}
      </div>
    </div>
  )
}

// ── DocumentLayout ────────────────────────────────────────────
export function DocumentLayout({
  title,
  documentNo,
  status,
  statusLabel,
  identity,
  metrics = [],
  meta = [],
  actions = [],
  primary,
  tabs,
  footer,
  visualFamily = 'sales',
  onBack,
  backLabel,
  activeTabKey,
  onTabChange,
  workflow,
  sidebar,
}: {
  /** Document type name, e.g. "Sales Invoice". */
  title: string
  documentNo?: string | null
  status?: string
  statusLabel?: string
  /** Counterparty shown once in the header (for example Customer + TIN). */
  identity?: DocumentIdentity
  /** Primary document figures shown once in the header. */
  metrics?: DocumentMetric[]
  meta?: DocumentMetaField[]
  workflow?: { steps: WorkflowStep[]; currentKey: string }
  actions?: ToolbarAction[]
  /** Primary Information section rendered between the header and the tabs. */
  primary?: React.ReactNode
  tabs: DocumentTab[]
  /** Compact immutable/system metadata at the bottom of the workspace. */
  footer?: React.ReactNode
  /** Family tint for shared transaction workspaces; never changes business behavior. */
  visualFamily?: TransactionWorkspaceFamily
  onBack?: () => void
  backLabel?: string
  activeTabKey?: string
  onTabChange?: (key: string) => void
  /** Optional transaction-specific sidebar. Omit when it would duplicate header or tab facts. */
  sidebar?: React.ReactNode
}) {
  const visibleTabs = tabs.filter(t => !t.hidden)
  const [internalTab, setInternalTab] = useState(visibleTabs[0]?.key ?? '')
  const activeKey = activeTabKey ?? internalTab
  const setActive = (k: string) => { if (onTabChange) onTabChange(k); else setInternalTab(k) }
  const resolvedActiveKey = visibleTabs.some(tab => tab.key === activeKey) ? activeKey : visibleTabs[0]?.key
  return (
    <section className={`pxl-transaction-workspace pxl-transaction-workspace--${visualFamily} space-y-2 rounded-md p-2`} aria-label={`${title} workspace`}>
      {/* Document header: identity, status, primary metrics, and actions live here once. */}
      <TransactionPageHeader
        title={title}
        documentNo={documentNo}
        status={status}
        statusLabel={statusLabel}
        identity={identity}
        metrics={metrics}
        meta={meta}
        actions={actions}
        onBack={onBack}
        backLabel={backLabel}
      />

      {workflow && workflow.steps.length > 0 && (
        <TransactionWorkflowBanner steps={workflow.steps} currentKey={workflow.currentKey} />
      )}

      {/* Primary Information — full width, before the tabs */}
      {primary}

      {/* Full-width compact tab bar — 12 tabs on one row, no horizontal
          scroll at 1920×1080 (it spans the whole content width, not the
          narrower content column beside the sidebar). */}
      <div className="overflow-hidden rounded border border-[var(--pxl-border-strong)]">
        <TransactionTabsBar tabs={tabs} activeKey={resolvedActiveKey || ''} onChange={setActive} />
      </div>

      {/* Active tab content */}
      <div className={sidebar ? 'pxl-transaction-content-grid grid min-w-0 items-start gap-2 lg:grid-cols-[minmax(0,1fr)_15rem] xl:grid-cols-[minmax(0,1fr)_16rem]' : ''}>
        <div className="min-w-0">
          {visibleTabs.map(tab => {
            const active = tab.key === resolvedActiveKey
            return (
              <div
                key={tab.key}
                id={`transaction-panel-${tab.key}`}
                aria-labelledby={`transaction-tab-${tab.key}`}
                aria-hidden={!active}
                hidden={!active}
                className="pxl-transaction-tab-panel min-w-0 w-full rounded border border-[var(--pxl-border-medium)] bg-white px-2.5 py-2 shadow-[var(--pxl-shadow-card)]"
                role="tabpanel">
                {tab.content}
              </div>
            )
          })}
        </div>
        {sidebar && <aside className="pxl-side-panel min-w-0 p-2.5" aria-label={`${title} summary`}>{sidebar}</aside>}
      </div>

      {footer && <footer className="pxl-caption px-1">{footer}</footer>}
    </section>
  )
}

export default DocumentLayout
