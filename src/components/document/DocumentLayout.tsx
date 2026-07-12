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
function DocumentToolbar({ actions }: { actions: ToolbarAction[] }) {
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
            className="px-3 py-1.5 rounded-md text-sm font-medium border border-gray-300 text-gray-700 hover:bg-gray-50">
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

// ── TransactionTabs ───────────────────────────────────────────
// ERP-style perspectives on the same document. Irrelevant tabs are
// hidden per document type (blueprint §4). Controlled or self-managed.
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
      <div className="border-b border-gray-200 flex items-center gap-1 overflow-x-auto" role="tablist">
        {visible.map(t => {
          const on = t.key === activeTab?.key
          return (
            <button
              key={t.key}
              role="tab"
              aria-selected={on}
              onClick={() => setActive(t.key)}
              className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 -mb-px transition-colors ${
                on ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
              {t.label}
              {t.badge != null && (
                <span className="ml-1.5 text-xs text-gray-400">{t.badge}</span>
              )}
            </button>
          )
        })}
      </div>
      <div className="pt-4" role="tabpanel">
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
  meta = [],
  workflow,
  actions = [],
  primary,
  tabs,
  rightRail,
  onBack,
  activeTabKey,
  onTabChange,
}: {
  /** Document type name, e.g. "Sales Invoice". */
  title: string
  documentNo?: string | null
  status?: string
  statusLabel?: string
  meta?: DocumentMetaField[]
  workflow?: { steps: WorkflowStep[]; currentKey: string }
  actions?: ToolbarAction[]
  /** Primary Information section rendered between the header and the tabs. */
  primary?: React.ReactNode
  tabs: DocumentTab[]
  /** Contextual cards (Financial Summary, Posting Validation, …) shown on wide screens. */
  rightRail?: React.ReactNode
  onBack?: () => void
  activeTabKey?: string
  onTabChange?: (key: string) => void
}) {
  return (
    <div className="space-y-4">
      {/* Header bar */}
      <div className="bg-white border border-gray-200 rounded-lg">
        <div className="px-6 py-4 flex flex-wrap items-start justify-between gap-4 border-b border-gray-100">
          <div className="min-w-0">
            <div className="flex items-center gap-2 text-xs text-gray-400">
              {onBack && (
                <button onClick={onBack} className="hover:text-gray-700" title="Back to list">← {title}s</button>
              )}
              {!onBack && <span>{title}</span>}
            </div>
            <div className="flex items-center gap-3 mt-1">
              <h1 className="text-lg font-semibold text-gray-900 truncate">
                {documentNo || <span className="text-gray-400">Unsaved {title}</span>}
              </h1>
              {status && <StatusBadge status={status} label={statusLabel} />}
            </div>
          </div>
          {actions.length > 0 && <DocumentToolbar actions={actions} />}
        </div>

        {/* Meta chips + workflow strip */}
        {(meta.length > 0 || workflow) && (
          <div className="px-6 py-3 flex flex-wrap items-center gap-x-6 gap-y-2">
            {meta.map((f, i) => (
              <div key={i} className="text-sm">
                <span className="text-gray-400">{f.label}: </span>
                <span className="text-gray-700 font-medium">{f.value ?? '—'}</span>
              </div>
            ))}
            {workflow && (
              <div className="ml-auto">
                <WorkflowStrip steps={workflow.steps} currentKey={workflow.currentKey} />
              </div>
            )}
          </div>
        )}
      </div>

      {/* Body: (primary info + tabs) + right rail */}
      <div className="flex flex-col lg:flex-row gap-4 items-start">
        <div className="flex-1 min-w-0 w-full space-y-4">
          {primary}
          <div className="bg-white border border-gray-200 rounded-lg px-6 py-4">
            <TransactionTabs tabs={tabs} activeKey={activeTabKey} onChange={onTabChange} />
          </div>
        </div>
        {rightRail && (
          <aside className="w-full lg:w-80 shrink-0 space-y-4">{rightRail}</aside>
        )}
      </div>
    </div>
  )
}

export default DocumentLayout
