/* eslint-disable react-refresh/only-export-components -- visual class constants are shared with these small presentation components. */
import type { ReactNode } from 'react'

// Shared presentation primitives for transaction workspace tabs.
// These are intentionally visual-only: no data fetching, routing, or business behavior.

export const ERP_SECTION = 'bg-white border border-gray-200 rounded'
export const ERP_SECTION_PAD = `${ERP_SECTION} p-3`
export const ERP_TABLE = 'w-full text-xs'
export const ERP_TABLE_WRAP = 'overflow-x-auto border border-gray-200 rounded'
export const ERP_THEAD = 'bg-gray-50 border-b border-gray-200'
export const ERP_TH = 'px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500 whitespace-nowrap'
export const ERP_TD = 'px-2 py-1.5 text-xs text-gray-700'
export const ERP_TD_NUM = `${ERP_TD} text-right font-mono tabular-nums`
export const ERP_EMPTY_CELL = 'px-3 py-4 text-center text-xs text-gray-400'
export const ERP_ROW_HOVER = 'hover:bg-gray-50'
export const ERP_TOTAL_ROW = 'border-t border-gray-200 bg-gray-50'

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
        <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-700">
          {title}
        </div>
        {description && (
          <div className="mt-0.5 text-[11px] leading-snug text-gray-500">
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
    <div className="px-3 py-4 text-center text-xs text-gray-400">
      {children}
    </div>
  )
}
