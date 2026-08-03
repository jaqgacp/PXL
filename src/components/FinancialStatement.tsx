import { useFinancialStatement, type FsColumn, type FsLine, type FsStatement } from '@/lib/financialStatement'

/**
 * The one financial statement renderer.
 *
 * There is deliberately no layout here for any particular statement. The line
 * hierarchy, the labels, the order and which line is a subtotal all come from
 * `fs_structure` and `account_fs_map`, through `fn_financial_statement_report`.
 * That is what lets a company re-present its accounts — a local GAAP or IFRS
 * change — without touching a component, and it is why the four statement pages
 * below are thin wrappers rather than four hand-built tables.
 */
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    .format(Math.abs(n) < 0.005 ? 0 : n)

export function FinancialStatementTable({
  lines, columns, emptyMessage,
}: {
  lines: FsLine[]
  columns: FsColumn[]
  emptyMessage: string
}) {
  if (!lines.length) {
    return (
      <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">
        {emptyMessage}
      </div>
    )
  }
  return (
    <div className="max-w-4xl bg-white border border-gray-200 rounded-lg overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="bg-gray-50 border-b border-gray-200">
          <tr>
            <th className="px-4 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500">Line</th>
            {columns.map(c => (
              <th key={c.key} className="px-4 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {lines.map(l => (
            <tr
              key={l.line_code}
              className={`border-b border-gray-100 ${l.is_subtotal ? 'bg-gray-50 font-semibold text-gray-900' : 'text-gray-700'}`}
            >
              <td className="px-4 py-1.5" style={{ paddingLeft: 16 + l.depth * 18 }}>
                {l.line_label}
                {l.line_role === 'cash_reconciliation' && (
                  <span className="ml-2 text-[10px] uppercase tracking-wide text-gray-400">reconciliation</span>
                )}
              </td>
              {columns.map(c => (
                <td key={c.key} className="px-4 py-1.5 text-right font-mono tabular-nums whitespace-nowrap">
                  {fmt(l[c.key])}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/** Shared page chrome: title, period controls, print. */
export function FinancialStatementPage({
  title, subtitle, periodStart, periodEnd, onPeriodStart, onPeriodEnd,
  periodStartLabel = 'From', periodEndLabel = 'to',
  companyId, statement, columns, emptyMessage, footnote,
}: {
  title: string
  subtitle: string
  periodStart: string
  periodEnd: string
  onPeriodStart: (v: string) => void
  onPeriodEnd: (v: string) => void
  periodStartLabel?: string
  periodEndLabel?: string
  companyId: string | null | undefined
  statement: FsStatement
  columns: FsColumn[]
  emptyMessage: string
  footnote?: string
}) {
  const { lines, loading, error } = useFinancialStatement(companyId, statement, periodStart, periodEnd)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">{title}</h1>
          <p className="text-sm text-gray-500 mt-0.5">{subtitle}</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <span className="text-xs text-gray-400">{periodStartLabel}</span>
        <input type="date" value={periodStart} onChange={e => onPeriodStart(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">{periodEndLabel}</span>
        <input type="date" value={periodEnd} onChange={e => onPeriodEnd(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      {error && (
        <div className="border border-red-200 bg-red-50 text-red-700 rounded-lg px-4 py-3 text-sm">{error}</div>
      )}

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">
          Select a company from the context bar above.
        </div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <FinancialStatementTable lines={lines} columns={columns} emptyMessage={emptyMessage} />
      )}

      {footnote && <p className="text-xs text-gray-500 max-w-4xl">{footnote}</p>}
    </div>
  )
}
