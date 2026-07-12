// ─────────────────────────────────────────────────────────────
// LineGrid — the shared professional line grid (Standard
// Transaction Workspace §5). Column-driven and group-aware so
// every document type supplies its own column set with R/O/H
// visibility. Read-only today (the document-of-record view);
// the API is shaped so an editable mode (onCellChange, keyboard
// navigation, §5/§7 account determination) can be added without
// breaking callers. Totals footer optional.
// ─────────────────────────────────────────────────────────────

export type LineColumnGroup = 'business' | 'withholding' | 'accounting' | 'dimensions' | 'reference' | 'system'

export type LineColumn<T> = {
  key: string
  header: string
  align?: 'left' | 'right' | 'center'
  group?: LineColumnGroup
  /** Hidden by default (column-picker candidate, §5 "H"). */
  hidden?: boolean
  render: (row: T, index: number) => React.ReactNode
  /** Footer/totals cell; when any column supplies one, the footer row renders. */
  footer?: React.ReactNode
}

export function LineGrid<T>({
  columns,
  rows,
  getRowKey,
  emptyLabel = 'No lines on this document.',
  onRowClick,
  selectedKey,
}: {
  columns: LineColumn<T>[]
  rows: T[]
  getRowKey: (row: T, index: number) => string
  emptyLabel?: string
  /** Row click (e.g. to open a Line Detail Panel). */
  onRowClick?: (row: T, index: number) => void
  /** Key of the currently-selected row, highlighted. */
  selectedKey?: string
}) {
  const visible = columns.filter(c => !c.hidden)
  const hasFooter = visible.some(c => c.footer != null)
  const alignCls = (a?: string) => (a === 'right' ? 'text-right' : a === 'center' ? 'text-center' : 'text-left')

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="bg-gray-50 border-b border-gray-200">
          <tr>
            {visible.map(c => (
              <th key={c.key}
                className={`px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${alignCls(c.align)}`}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {rows.length === 0 ? (
            <tr><td colSpan={visible.length} className="px-3 py-8 text-center text-sm text-gray-400">{emptyLabel}</td></tr>
          ) : rows.map((row, i) => {
            const key = getRowKey(row, i)
            return (
            <tr key={key}
              onClick={onRowClick ? () => onRowClick(row, i) : undefined}
              className={`${onRowClick ? 'cursor-pointer' : ''} ${selectedKey === key ? 'bg-blue-50/60' : 'hover:bg-gray-50/60'}`}>
              {visible.map(c => (
                <td key={c.key} className={`px-3 py-2 text-xs text-gray-800 ${alignCls(c.align)}`}>
                  {c.render(row, i)}
                </td>
              ))}
            </tr>
          )})}
        </tbody>
        {hasFooter && rows.length > 0 && (
          <tfoot>
            <tr className="border-t-2 border-gray-200 bg-gray-50/70">
              {visible.map(c => (
                <td key={c.key} className={`px-3 py-2 text-xs font-semibold text-gray-900 ${alignCls(c.align)}`}>
                  {c.footer}
                </td>
              ))}
            </tr>
          </tfoot>
        )}
      </table>
    </div>
  )
}

export default LineGrid
