import { useState, useRef, useEffect, useLayoutEffect, useCallback } from 'react'
import { createPortal } from 'react-dom'

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
        const cls =
          state === 'current' ? 'bg-blue-50 text-blue-700 font-semibold' :
          state === 'done' ? 'bg-gray-100 text-gray-600' :
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
    const base = 'px-2.5 py-1 rounded text-xs font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed'
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
            className={`px-2.5 py-1 rounded text-xs font-medium ${inverse
              ? 'border border-white/30 bg-white/10 text-white hover:bg-white/20'
              : 'border border-gray-300 text-gray-700 hover:bg-gray-50'}`}>
            More ▾
          </button>
          {openMore && menuPosition && createPortal(
            <div
              ref={menuRef}
              className="fixed w-56 overflow-y-auto rounded border border-gray-200 bg-white py-1 shadow-xl ring-1 ring-black/10 z-[9999]"
              style={{
                top: menuPosition.top,
                left: menuPosition.left,
                maxHeight: menuPosition.maxHeight,
                transformOrigin: menuPosition.placement === 'top' ? 'bottom right' : 'top right',
              }}>
              {more.map(a => (
                <button
                  key={a.key}
                  onClick={() => { setOpenMore(false); a.onClick() }}
                  disabled={a.disabled}
                  title={a.title}
                  className={`w-full text-left px-3 py-1.5 text-xs disabled:opacity-40 disabled:cursor-not-allowed ${
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
    tone === 'success' ? 'bg-green-400' :
    tone === 'warning' ? 'bg-orange-400' :
    tone === 'error' ? 'bg-red-400' :
    tone === 'info' ? 'bg-blue-400' :
    'bg-white/45'
  return (
    <span title={title || label} className="inline-flex items-center gap-1.5 rounded border border-white/15 bg-white/8 px-2 py-0.5 text-[10px] font-medium text-white/90">
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
  return (
    <div
      className="flex items-stretch w-full min-w-0 px-1"
      role="tablist"
      style={{ backgroundColor: 'color-mix(in srgb, var(--transaction-accent, #14532d) 5%, white)' }}>
      {visible.map(t => {
        const on = t.key === activeKey
        return (
          <button
            key={t.key}
            role="tab"
            aria-selected={on}
            onClick={() => onChange(t.key)}
            title={t.label}
            style={on ? { borderColor: 'var(--transaction-accent, #111827)', color: 'var(--transaction-accent, #111827)' } : undefined}
            className={`flex-1 min-w-0 px-1.5 py-2 text-[11px] leading-none whitespace-nowrap border-b-2 transition-colors ${
              on
                ? 'font-semibold'
                : 'border-transparent text-gray-500 font-medium hover:text-gray-800 hover:bg-white/60'}`}>
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
    <section className="space-y-2 rounded-md p-2" style={workspaceStyle} aria-label={`${title} workspace`}>
      {/* Document header: identity, status, primary metrics, and actions live here once. */}
      <header className="rounded text-white shadow-sm overflow-hidden" style={headerStyle}>
        <div className="px-3 py-2 flex flex-col xl:flex-row xl:items-center gap-2.5">
          <div className="flex items-start gap-2.5 min-w-0 xl:w-[37%]">
            {onBack && (
              <button onClick={onBack} className="mt-0.5 text-white/60 hover:text-white" title={`Back to ${title}s`} aria-label={`Back to ${title}s`}>
                ←
              </button>
            )}
            <div className="min-w-0">
              <div className="text-[10px] font-semibold uppercase tracking-[0.16em] text-white/55">{title}</div>
              <div className="flex items-center gap-1.5 mt-0.5 min-w-0 flex-wrap">
                <h1 className="text-lg leading-tight font-semibold tracking-tight truncate">
                  {documentNo || `Unsaved ${title}`}
                </h1>
                {status && <HeaderStateChip value={statusLabel || status} tone={statusTone(status)} label="Document status" />}
                {meta.map((f, i) => <HeaderStateChip key={i} value={f.value} tone={f.tone} label={f.label} />)}
              </div>
              {identity && (
                <div className="mt-0.5 flex items-center gap-2 min-w-0">
                  <span className="text-xs font-medium text-white/90 truncate">{identity.name}</span>
                  {identity.secondary && <span className="text-[11px] font-mono text-white/60 truncate">{identity.secondary}</span>}
                </div>
              )}
            </div>
          </div>

          {metrics.length > 0 && (
            <dl className="grid grid-cols-3 gap-0 min-w-0 xl:flex-1 border-y xl:border-y-0 xl:border-x border-white/15">
              {metrics.map(metric => (
                <div key={metric.label} className="px-2.5 py-0.5 xl:py-0 min-w-0 xl:text-right">
                  <dt className="text-[9px] font-semibold uppercase tracking-wider text-white/50 truncate">{metric.label}</dt>
                  <dd className={`mt-0.5 font-mono tabular-nums truncate ${metric.emphasis ? 'text-base font-semibold text-white' : 'text-sm font-medium text-white/90'}`}>
                    {metric.value}
                  </dd>
                </div>
              ))}
            </dl>
          )}

          {actions.length > 0 && <div className="xl:ml-auto shrink-0"><DocumentToolbar actions={actions} inverse /></div>}
        </div>
      </header>

      {/* Primary Information — full width, before the tabs */}
      {primary}

      {/* Full-width compact tab bar — 12 tabs on one row, no horizontal
          scroll at 1920×1080 (it spans the whole content width, not the
          narrower content column beside the sidebar). */}
      <div className="border border-gray-200 rounded overflow-hidden">
        <TransactionTabsBar tabs={tabs} activeKey={activeKey} onChange={setActive} />
      </div>

      {/* Active tab content */}
      <div className="min-w-0 w-full bg-white border border-gray-200 rounded px-3 py-2.5" role="tabpanel">
        {activeTab?.content}
      </div>

      {footer && <footer className="px-1 text-[10px] text-gray-500">{footer}</footer>}
    </section>
  )
}

export default DocumentLayout
