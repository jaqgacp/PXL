import { useState, useRef, useEffect } from 'react'
import { StatusBadge } from '@/components/ui/shared'

// ─────────────────────────────────────────────────────────────
// PXL Standard Transaction Workspace — DocumentLayout shell
//
// The canonical layout every posting document converges onto
// (DEC-013 / PXL_STANDARD_TRANSACTION_WORKSPACE.md §"Standard Page
// Structure"; blueprint §3/§15). "Build first — everything else
// slots into it." Pure presentational: no data fetching, no posting
// behavior. Reuses the shared.tsx atoms; never forks StatusBadge.
// ─────────────────────────────────────────────────────────────

export type WorkflowStep = { key: string; label: string }

export type DocumentMetaField = {
  label: string
  value: React.ReactNode
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
        const cls =
          state === 'current' ? 'bg-blue-50 text-blue-700 font-semibold' :
          state === 'done' ? 'bg-green-50 text-green-700' :
          'bg-gray-100 text-gray-400'
        return (
          <li key={step.key} className="flex items-center gap-1">
            <span className={`inline-flex items-center px-2 py-0.5 rounded ${cls}`}>{step.label}</span>
            {i < steps.length - 1 && <span className="text-gray-300" aria-hidden>→</span>}
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
function DocumentToolbar({ actions, inverse = false }: { actions: ToolbarAction[]; inverse?: boolean }) {
  const [openMore, setOpenMore] = useState(false)
  const moreRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!openMore) return
    const onDoc = (e: MouseEvent) => {
      if (moreRef.current && !moreRef.current.contains(e.target as Node)) setOpenMore(false)
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [openMore])

  const visible = actions.filter(a => !a.hidden)
  const primary = visible.filter(a => (a.group ?? 'primary') === 'primary')
  const more = visible.filter(a => a.group === 'more')

  const btnCls = (a: ToolbarAction) => {
    const base = 'px-3 py-1.5 rounded-md text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed'
    if (inverse) {
      if (a.variant === 'primary') return `${base} bg-white text-gray-900 hover:bg-gray-100 shadow-sm`
      if (a.variant === 'danger') return `${base} border border-red-200/60 bg-red-950/20 text-red-50 hover:bg-red-950/35`
      return `${base} border border-white/30 bg-white/10 text-white hover:bg-white/20`
    }
    if (a.variant === 'primary') return `${base} bg-gray-900 text-white hover:bg-gray-800 disabled:hover:bg-gray-900`
    if (a.variant === 'danger') return `${base} border border-red-300 text-red-700 hover:bg-red-50`
    return `${base} border border-gray-300 text-gray-700 hover:bg-gray-50`
  }

  return (
    <div className="flex items-center gap-2">
      {primary.map(a => (
        <button key={a.key} onClick={a.onClick} disabled={a.disabled} title={a.title} className={btnCls(a)}>
          {a.label}
        </button>
      ))}
      {more.length > 0 && (
        <div className="relative" ref={moreRef}>
          <button
            onClick={() => setOpenMore(o => !o)}
            className={`px-3 py-1.5 rounded-md text-sm font-medium ${inverse
              ? 'border border-white/30 bg-white/10 text-white hover:bg-white/20'
              : 'border border-gray-300 text-gray-700 hover:bg-gray-50'}`}>
            More ▾
          </button>
          {openMore && (
            <div className="absolute right-0 mt-1 w-48 bg-white border border-gray-200 rounded-md shadow-lg z-20 py-1">
              {more.map(a => (
                <button
                  key={a.key}
                  onClick={() => { setOpenMore(false); a.onClick() }}
                  disabled={a.disabled}
                  title={a.title}
                  className={`w-full text-left px-3 py-1.5 text-sm disabled:opacity-40 disabled:cursor-not-allowed ${
                    a.variant === 'danger' ? 'text-red-700 hover:bg-red-50' : 'text-gray-700 hover:bg-gray-50'}`}>
                  {a.label}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
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
  return (
    <div className="flex items-stretch w-full min-w-0 px-1" role="tablist">
      {visible.map(t => {
        const on = t.key === activeKey
        return (
          <button
            key={t.key}
            role="tab"
            aria-selected={on}
            onClick={() => onChange(t.key)}
            title={t.label}
            className={`flex-1 min-w-0 px-1.5 py-2.5 text-[11px] xl:text-xs leading-none whitespace-nowrap border-b-2 transition-colors ${
              on
                ? 'border-gray-900 text-gray-900 font-semibold'
                : 'border-transparent text-gray-500 font-medium hover:text-gray-800 hover:bg-gray-50'}`}>
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
      <div className="pt-4" role="tabpanel">{activeTab?.content}</div>
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
  workflow,
  actions = [],
  primary,
  tabs,
  footer,
  accentColor = '#14532d',
  onBack,
  activeTabKey,
  onTabChange,
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
  /** Company-controlled transaction accent. Cards remain white; the shell uses a 3% tint. */
  accentColor?: string
  onBack?: () => void
  activeTabKey?: string
  onTabChange?: (key: string) => void
}) {
  const visibleTabs = tabs.filter(t => !t.hidden)
  const [internalTab, setInternalTab] = useState(visibleTabs[0]?.key ?? '')
  const activeKey = activeTabKey ?? internalTab
  const setActive = (k: string) => { if (onTabChange) onTabChange(k); else setInternalTab(k) }
  const activeTab = visibleTabs.find(t => t.key === activeKey) ?? visibleTabs[0]

  const workspaceStyle = {
    '--transaction-accent': accentColor,
    backgroundColor: 'color-mix(in srgb, var(--transaction-accent) 3%, white)',
  } as React.CSSProperties
  const headerStyle = {
    backgroundColor: 'color-mix(in srgb, var(--transaction-accent) 78%, #111827)',
  } as React.CSSProperties

  return (
    <section className="space-y-3 rounded-xl p-3" style={workspaceStyle} aria-label={`${title} workspace`}>
      {/* Document header: identity, status, primary metrics, and actions live here once. */}
      <header className="rounded-lg text-white shadow-sm overflow-hidden" style={headerStyle}>
        <div className="px-4 py-3 flex flex-col xl:flex-row xl:items-center gap-3">
          <div className="flex items-start gap-3 min-w-0 xl:w-[36%]">
            {onBack && (
              <button onClick={onBack} className="mt-0.5 text-white/60 hover:text-white" title={`Back to ${title}s`} aria-label={`Back to ${title}s`}>
                ←
              </button>
            )}
            <div className="min-w-0">
              <div className="text-[10px] font-semibold uppercase tracking-[0.16em] text-white/55">{title}</div>
              <div className="flex items-center gap-2 mt-0.5 min-w-0">
                <h1 className="text-xl leading-tight font-semibold tracking-tight truncate">
                  {documentNo || `Unsaved ${title}`}
                </h1>
                {status && <StatusBadge status={status} label={statusLabel} />}
              </div>
              {identity && (
                <div className="mt-1 flex items-center gap-2 min-w-0">
                  <span className="text-sm font-medium text-white truncate">{identity.name}</span>
                  {identity.secondary && <span className="text-[11px] font-mono text-white/60 truncate">{identity.secondary}</span>}
                </div>
              )}
            </div>
          </div>

          {metrics.length > 0 && (
            <dl className="grid grid-cols-3 gap-0 min-w-0 xl:flex-1 border-y xl:border-y-0 xl:border-x border-white/15">
              {metrics.map(metric => (
                <div key={metric.label} className="px-3 py-1 xl:py-0 min-w-0 xl:text-right">
                  <dt className="text-[9px] font-semibold uppercase tracking-wider text-white/50 truncate">{metric.label}</dt>
                  <dd className={`mt-0.5 font-mono tabular-nums truncate ${metric.emphasis ? 'text-lg font-semibold text-white' : 'text-base font-medium text-white/90'}`}>
                    {metric.value}
                  </dd>
                </div>
              ))}
            </dl>
          )}

          {actions.length > 0 && <div className="xl:ml-auto shrink-0"><DocumentToolbar actions={actions} inverse /></div>}
        </div>
      </header>

      {/* One-line document state strip. */}
      {(meta.length > 0 || workflow) && (
        <div className="bg-white border border-gray-200 rounded-lg px-3 py-1.5 flex items-center gap-x-4 min-w-0 overflow-hidden">
          {meta.map((f, i) => (
            <div key={i} className="flex items-center gap-1.5 shrink-0 text-xs">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{f.label}</span>
              <span className="text-gray-700 font-medium">{f.value ?? '—'}</span>
            </div>
          ))}
          {workflow && (
            <div className="ml-auto flex items-center gap-2 min-w-0 overflow-hidden">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400 shrink-0">Workflow</span>
              <WorkflowStrip steps={workflow.steps} currentKey={workflow.currentKey} />
            </div>
          )}
        </div>
      )}

      {/* Primary Information — full width, before the tabs */}
      {primary}

      {/* Full-width compact tab bar — 12 tabs on one row, no horizontal
          scroll at 1920×1080 (it spans the whole content width, not the
          narrower content column beside the sidebar). */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <TransactionTabsBar tabs={tabs} activeKey={activeKey} onChange={setActive} />
      </div>

      {/* Active tab content */}
      <div className="min-w-0 w-full bg-white border border-gray-200 rounded-lg px-4 py-3" role="tabpanel">
        {activeTab?.content}
      </div>

      {footer && <footer className="px-1 text-[10px] text-gray-500">{footer}</footer>}
    </section>
  )
}

export default DocumentLayout
