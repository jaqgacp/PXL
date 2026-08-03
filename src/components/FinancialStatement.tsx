import { Fragment, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  useFinancialStatement, useFsLineAccounts,
  type ComparativeFsLine, type FsColumn, type FsLine, type FsNoteItem, type FsStatement,
} from '@/lib/financialStatement'

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

const pct = (n: number | null) => (n === null ? '—' : `${n.toFixed(1)}%`)

/**
 * The accounts behind a line, opened in place.
 *
 * Drill-down and supporting schedule are the same question, so they come from
 * the same RPC and are signed by the same rule as the line itself — which is
 * why the rows here always add up to the row they opened from.
 */
function LineAccounts({
  companyId, statement, lineCode, periodStart, periodEnd, priorStart, priorEnd, colSpan, comparative,
}: {
  companyId: string
  statement: FsStatement
  lineCode: string
  periodStart: string
  periodEnd: string
  priorStart?: string | null
  priorEnd?: string | null
  colSpan: number
  comparative: boolean
}) {
  const { accounts, loading, error } = useFsLineAccounts(
    companyId, statement, lineCode, periodStart, periodEnd, priorStart, priorEnd)

  const ledger = (accountId: string, from: string, to: string) =>
    `/account-detail-ledger?accountId=${accountId}&dateFrom=${from}&dateTo=${to}`

  return (
    <tr className="bg-blue-50/30">
      <td colSpan={colSpan} className="px-0 py-0">
        {loading ? (
          <div className="px-8 py-3 text-xs text-gray-400">Loading accounts…</div>
        ) : error ? (
          <div className="px-8 py-3 text-xs text-red-600">{error}</div>
        ) : accounts.length === 0 ? (
          <div className="px-8 py-3 text-xs text-gray-400">No accounts carry a balance on this line.</div>
        ) : (
          <table className="w-full text-xs">
            <tbody>
              {accounts.map(a => (
                <tr key={a.account_id} className="border-b border-blue-100/60 last:border-0">
                  <td className="py-1 pl-10 pr-4 text-gray-600">
                    <Link to={ledger(a.account_id, periodStart, periodEnd)}
                      className="text-blue-700 hover:text-blue-900">
                      {a.account_code} — {a.account_name}
                    </Link>
                  </td>
                  <td className="py-1 px-4 text-right font-mono tabular-nums text-gray-700">{fmt(a.current_amount)}</td>
                  {comparative && (
                    <>
                      <td className="py-1 px-4 text-right font-mono tabular-nums text-gray-500">
                        {priorStart && priorEnd ? (
                          <Link to={ledger(a.account_id, priorStart, priorEnd)}
                            className="text-blue-600 hover:text-blue-900">{fmt(a.prior_amount)}</Link>
                        ) : fmt(a.prior_amount)}
                      </td>
                      <td className="py-1 px-4 text-right font-mono tabular-nums text-gray-500">{fmt(a.variance_amount)}</td>
                      <td className="py-1 px-4 text-right font-mono tabular-nums text-gray-400">{pct(a.variance_percent)}</td>
                    </>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </td>
    </tr>
  )
}

export function FinancialStatementTable({
  lines, columns, emptyMessage, companyId, statement, periodStart, periodEnd,
}: {
  lines: FsLine[]
  columns: FsColumn[]
  emptyMessage: string
  companyId?: string | null
  statement?: FsStatement
  periodStart?: string
  periodEnd?: string
}) {
  const [open, setOpen] = useState<string | null>(null)
  const canDrill = Boolean(companyId && statement && periodStart && periodEnd)

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
            <Fragment key={l.line_code}>
              <tr
                className={`border-b border-gray-100 ${l.is_subtotal ? 'bg-gray-50 font-semibold text-gray-900' : 'text-gray-700'} ${canDrill ? 'cursor-pointer hover:bg-blue-50/40' : ''}`}
                onClick={canDrill ? () => setOpen(open === l.line_code ? null : l.line_code) : undefined}
              >
                <td className="px-4 py-1.5" style={{ paddingLeft: 16 + l.depth * 18 }}>
                  {canDrill && (
                    <span className="inline-block w-3 text-gray-400 select-none">
                      {open === l.line_code ? '▾' : '▸'}
                    </span>
                  )}
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
              {canDrill && open === l.line_code && (
                <LineAccounts
                  companyId={companyId!} statement={statement!} lineCode={l.line_code}
                  periodStart={periodStart!} periodEnd={periodEnd!}
                  colSpan={1 + columns.length} comparative={false}
                />
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/**
 * The comparative statement.
 *
 * Same governed lines, same order, same subtotal hierarchy as the single-period
 * view — because it is the same reporting contract, called twice and joined on
 * the line code. Nothing here computes an amount.
 */
export function ComparativeStatementTable({
  lines, currentLabel, priorLabel, emptyMessage,
  companyId, statement, periodStart, periodEnd, priorStart, priorEnd,
}: {
  lines: ComparativeFsLine[]
  currentLabel: string
  priorLabel: string
  emptyMessage: string
  companyId: string
  statement: FsStatement
  periodStart: string
  periodEnd: string
  priorStart: string
  priorEnd: string
}) {
  const [open, setOpen] = useState<string | null>(null)

  if (!lines.length) {
    return (
      <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">
        {emptyMessage}
      </div>
    )
  }
  return (
    <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="bg-gray-50 border-b border-gray-200">
          <tr>
            <th className="px-4 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500">Line</th>
            <th className="px-4 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{currentLabel}</th>
            <th className="px-4 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{priorLabel}</th>
            <th className="px-4 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">Variance</th>
            <th className="px-4 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">%</th>
          </tr>
        </thead>
        <tbody>
          {lines.map(l => (
            <Fragment key={l.line_code}>
              <tr
                className={`border-b border-gray-100 cursor-pointer hover:bg-blue-50/40 ${l.is_subtotal ? 'bg-gray-50 font-semibold text-gray-900' : 'text-gray-700'}`}
                onClick={() => setOpen(open === l.line_code ? null : l.line_code)}
              >
                <td className="px-4 py-1.5" style={{ paddingLeft: 16 + l.depth * 18 }}>
                  <span className="inline-block w-3 text-gray-400 select-none">
                    {open === l.line_code ? '▾' : '▸'}
                  </span>
                  {l.line_label}
                  {l.line_role === 'cash_reconciliation' && (
                    <span className="ml-2 text-[10px] uppercase tracking-wide text-gray-400">reconciliation</span>
                  )}
                </td>
                <td className="px-4 py-1.5 text-right font-mono tabular-nums whitespace-nowrap">{fmt(l.current_amount)}</td>
                <td className="px-4 py-1.5 text-right font-mono tabular-nums whitespace-nowrap text-gray-600">{fmt(l.prior_amount)}</td>
                <td className={`px-4 py-1.5 text-right font-mono tabular-nums whitespace-nowrap ${l.variance_amount >= 0 ? 'text-gray-700' : 'text-red-600'}`}>
                  {fmt(l.variance_amount)}
                </td>
                <td className={`px-4 py-1.5 text-right font-mono tabular-nums whitespace-nowrap text-xs ${l.variance_percent === null ? 'text-gray-400' : l.variance_percent >= 0 ? 'text-gray-600' : 'text-red-600'}`}>
                  {pct(l.variance_percent)}
                </td>
              </tr>
              {open === l.line_code && (
                <LineAccounts
                  companyId={companyId} statement={statement} lineCode={l.line_code}
                  periodStart={periodStart} periodEnd={periodEnd}
                  priorStart={priorStart} priorEnd={priorEnd}
                  colSpan={5} comparative
                />
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/**
 * Basic statement notes.
 *
 * Every item names the configuration or ledger fact behind it and says whether
 * that fact is configured, so an unset policy reads as unset rather than as a
 * default. That flag is the whole point: an accountant needs to know which
 * disclosures are real and which are still blank.
 */
export function StatementNotes({ notes }: { notes: FsNoteItem[] }) {
  if (!notes.length) return null
  const codes = [...new Set(notes.map(n => n.note_code))]
  return (
    <div className="space-y-3">
      {codes.map((code, i) => {
        const items = notes.filter(n => n.note_code === code)
        return (
          <div key={code} className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-2 border-b border-gray-100 bg-gray-50/60">
              <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-500">
                Note {i + 1} — {items[0].note_title}
              </span>
            </div>
            <table className="w-full text-sm">
              <tbody>
                {items.map(n => (
                  <tr key={n.item_label} className="border-b border-gray-50 last:border-0 align-top">
                    <td className="px-4 py-1.5 text-gray-500 w-64">{n.item_label}</td>
                    <td className="px-4 py-1.5 text-gray-800">
                      {n.item_value}
                      {!n.is_configured && (
                        <span className="ml-2 text-[10px] uppercase tracking-wide text-amber-700">not configured</span>
                      )}
                      <div className="text-[11px] text-gray-400 mt-0.5">{n.item_source}</div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )
      })}
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
        <FinancialStatementTable
          lines={lines} columns={columns} emptyMessage={emptyMessage}
          companyId={companyId} statement={statement}
          periodStart={periodStart} periodEnd={periodEnd}
        />
      )}

      {footnote && <p className="text-xs text-gray-500 max-w-4xl">{footnote}</p>}
    </div>
  )
}
