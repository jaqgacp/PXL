/* eslint-disable react-refresh/only-export-components -- visual class constants are shared with these small presentation components. */
import { useState, type ReactNode } from 'react'

// Shared presentation primitives for transaction workspace tabs.
// These are intentionally visual-only: no data fetching, routing, or business behavior.

export const ERP_SECTION = 'pxl-transaction-card'
export const ERP_SECTION_PAD = `${ERP_SECTION} p-3`
export const ERP_TABLE = 'pxl-data-grid w-full'
export const ERP_TABLE_WRAP = 'overflow-x-auto rounded border border-[var(--pxl-border-medium)]'
export const ERP_THEAD = 'border-b border-[var(--pxl-border-medium)]'
export const ERP_TH = 'px-2 py-1.5 whitespace-nowrap'
export const ERP_TD = 'px-2 py-1.5 pxl-body-text'
export const ERP_TD_NUM = `${ERP_TD} text-right font-mono tabular-nums`
export const ERP_EMPTY_CELL = 'pxl-empty-state'
export const ERP_ROW_HOVER = 'hover:bg-[var(--pxl-surface-table-hover)]'
export const ERP_TOTAL_ROW = 'border-t border-[var(--pxl-border-strong)] bg-[var(--pxl-surface-table-selected)]'

export function ErpSectionHeader({
  title,
  description,
  badge,
  className = '',
}: {
  title: string
  description?: ReactNode
  badge?: ReactNode
  className?: string
}) {
  return (
    <div className={`flex items-start justify-between gap-3 ${className}`}>
      <div className="min-w-0">
        <div className="pxl-section-title">
          {title}
        </div>
        {description && (
          <div className="pxl-caption mt-1 leading-snug">
            {description}
          </div>
        )}
      </div>
      {badge && <div className="shrink-0">{badge}</div>}
    </div>
  )
}

export function CompactEmptyState({ children }: { children: ReactNode }) {
  return (
    <div className="pxl-empty-state">
      {children}
    </div>
  )
}

export function TransactionPanel({
  title,
  description,
  badge,
  actions,
  children,
  collapsible = false,
  defaultCollapsed = false,
  className = '',
  contentClassName = 'p-4',
}: {
  title: string
  description?: ReactNode
  badge?: ReactNode
  actions?: ReactNode
  children: ReactNode
  collapsible?: boolean
  defaultCollapsed?: boolean
  className?: string
  contentClassName?: string
}) {
  const [collapsed, setCollapsed] = useState(defaultCollapsed)

  return (
    <section className={`${ERP_SECTION} ${className}`}>
      <div className="flex items-start justify-between gap-3 border-b border-[var(--pxl-border-subtle)] px-4 py-3">
        <div className="min-w-0">
          {collapsible ? (
            <button
              type="button"
              onClick={() => setCollapsed(open => !open)}
              className="pxl-section-title flex items-center gap-2 text-left"
              aria-expanded={!collapsed}
            >
              <span aria-hidden>{collapsed ? '▸' : '▾'}</span>
              <span>{title}</span>
            </button>
          ) : (
            <div className="pxl-section-title">{title}</div>
          )}
          {description && <div className="pxl-caption mt-1 leading-snug">{description}</div>}
        </div>
        {(badge || actions) && (
          <div className="flex shrink-0 items-center gap-2">
            {badge}
            {actions}
          </div>
        )}
      </div>
      {!collapsed && <div className={contentClassName}>{children}</div>}
    </section>
  )
}
