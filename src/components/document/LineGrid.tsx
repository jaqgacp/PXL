import { Fragment, useEffect, useRef, useState } from 'react'

// ────────────────────────────────────────────────────────────
// LineGrid — the shared professional transaction grid. It supports
// role-oriented column profiles, an individual column chooser, inline
// expandable detail, and a compact accounting totals band.
// ────────────────────────────────────────────────────────────

export type LineColumnGroup = 'business' | 'withholding' | 'accounting' | 'dimensions' | 'reference' | 'system'

export type LineColumn<T> = {
  key: string
  header: string
  align?: 'left' | 'right' | 'center'
  group?: LineColumnGroup
  hidden?: boolean
  render: (row: T, index: number) => React.ReactNode
  footer?: React.ReactNode
  minWidth?: string
}

export type LineColumnProfile = {
  key: string
  label: string
  columnKeys: string[]
}

export type LineSummaryMetric = {
  key: string
  label: string
  value: React.ReactNode
  emphasis?: boolean
}

export function LineGrid<T>({
  columns,
  rows,
  getRowKey,
  emptyLabel = 'No lines on this document.',
  onRowClick,
  selectedKey,
  renderExpandedRow,
  profiles = [],
  initialProfileKey,
  summary = [],
}: {
  columns: LineColumn<T>[]
  rows: T[]
  getRowKey: (row: T, index: number) => string
  emptyLabel?: string
  onRowClick?: (row: T, index: number) => void
  selectedKey?: string
  renderExpandedRow?: (row: T, index: number) => React.ReactNode
  profiles?: LineColumnProfile[]
  initialProfileKey?: string
  summary?: LineSummaryMetric[]
}) {
  const firstProfile = profiles.find(profile => profile.key === initialProfileKey) ?? profiles[0]
  const [visibleKeys, setVisibleKeys] = useState<Set<string>>(
    () => new Set(firstProfile?.columnKeys ?? columns.filter(column => !column.hidden).map(column => column.key))
  )
  const [activeProfile, setActiveProfile] = useState(firstProfile?.key ?? 'custom')
  const [pickerOpen, setPickerOpen] = useState(false)
  const pickerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!pickerOpen) return
    const close = (event: MouseEvent) => {
      if (pickerRef.current && !pickerRef.current.contains(event.target as Node)) setPickerOpen(false)
    }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [pickerOpen])

  const applyProfile = (profile: LineColumnProfile) => {
    setVisibleKeys(new Set(profile.columnKeys))
    setActiveProfile(profile.key)
  }

  const toggleColumn = (key: string) => {
    setVisibleKeys(current => {
      const next = new Set(current)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
    setActiveProfile('custom')
  }

  const visible = columns.filter(column => visibleKeys.has(column.key))
  const hasFooter = visible.some(column => column.footer != null)
  const alignClass = (align?: string) => align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : 'text-left'
  const detailColSpan = visible.length + (renderExpandedRow ? 1 : 0)

  return (
    <div>
      <div className="flex items-center justify-between gap-3 pb-2">
        <div className="flex items-center gap-1 min-w-0">
          <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mr-1">Columns</span>
          {profiles.map(profile => (
            <button key={profile.key} type="button" onClick={() => applyProfile(profile)}
              className={`px-2 py-1 rounded text-[11px] font-medium ${activeProfile === profile.key ? 'bg-gray-900 text-white' : 'text-gray-500 hover:bg-gray-100 hover:text-gray-800'}`}>
              {profile.label}
            </button>
          ))}
        </div>
        <div className="relative shrink-0" ref={pickerRef}>
          <button type="button" onClick={() => setPickerOpen(open => !open)}
            className="px-2.5 py-1 border border-gray-300 rounded text-[11px] font-medium text-gray-600 hover:bg-gray-50">
            Choose columns ▾
          </button>
          {pickerOpen && (
            <div className="absolute right-0 top-full mt-1 z-30 w-60 max-h-80 overflow-y-auto bg-white border border-gray-200 rounded-md shadow-xl p-1.5">
              {columns.map(column => (
                <label key={column.key} className="flex items-center gap-2 px-2 py-1.5 text-xs text-gray-700 rounded hover:bg-gray-50 cursor-pointer">
                  <input type="checkbox" checked={visibleKeys.has(column.key)} onChange={() => toggleColumn(column.key)} className="rounded border-gray-300" />
                  <span>{column.header}</span>
                </label>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="overflow-x-auto border border-gray-200 rounded-md">
        <table className="min-w-full w-max text-xs">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              {renderExpandedRow && <th className="w-7 px-1 py-2" aria-label="Expand line" />}
              {visible.map(column => (
                <th key={column.key} style={column.minWidth ? { minWidth: column.minWidth } : undefined}
                  className={`px-2 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${alignClass(column.align)}`}>
                  {column.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.length === 0 ? (
              <tr><td colSpan={detailColSpan} className="px-3 py-8 text-center text-sm text-gray-400">{emptyLabel}</td></tr>
            ) : rows.map((row, index) => {
              const key = getRowKey(row, index)
              const expanded = selectedKey === key
              return (
                <Fragment key={key}>
                  <tr onClick={onRowClick ? () => onRowClick(row, index) : undefined}
                    aria-expanded={renderExpandedRow ? expanded : undefined}
                    className={`${onRowClick ? 'cursor-pointer' : ''} ${expanded ? 'bg-blue-50/60' : 'hover:bg-gray-50/60'}`}>
                    {renderExpandedRow && (
                      <td className="px-1 py-1.5 text-center text-gray-400"><span aria-hidden>{expanded ? '▾' : '›'}</span></td>
                    )}
                    {visible.map(column => (
                      <td key={column.key} className={`px-2 py-1.5 text-[11px] text-gray-800 whitespace-nowrap ${alignClass(column.align)}`}>
                        {column.render(row, index)}
                      </td>
                    ))}
                  </tr>
                  {expanded && renderExpandedRow && (
                    <tr className="bg-gray-50/70">
                      <td colSpan={detailColSpan} className="p-0">{renderExpandedRow(row, index)}</td>
                    </tr>
                  )}
                </Fragment>
              )
            })}
          </tbody>
          {hasFooter && rows.length > 0 && (
            <tfoot>
              <tr className="border-t-2 border-gray-200 bg-gray-50/70">
                {renderExpandedRow && <td />}
                {visible.map(column => (
                  <td key={column.key} className={`px-2 py-2 text-[11px] font-semibold text-gray-900 ${alignClass(column.align)}`}>
                    {column.footer}
                  </td>
                ))}
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      {summary.length > 0 && (
        <dl className="mt-2 flex items-center justify-end gap-x-5 gap-y-2 flex-wrap rounded-md bg-gray-50 border border-gray-100 px-3 py-2">
          {summary.map(metric => (
            <div key={metric.key} className="flex items-baseline gap-1.5 whitespace-nowrap">
              <dt className="text-[10px] uppercase tracking-wide text-gray-400">{metric.label}</dt>
              <dd className={`text-xs font-mono tabular-nums ${metric.emphasis ? 'font-bold text-gray-900' : 'font-medium text-gray-700'}`}>{metric.value}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  )
}

export default LineGrid
