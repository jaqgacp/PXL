import { useState } from 'react'
import { useAppCtx } from '@/lib/context'
import { ComparativeStatementTable, StatementNotes } from '@/components/FinancialStatement'
import {
  useComparativePeriod, useComparativeFinancialStatement, useFinancialStatementNotes,
  type FsStatement,
} from '@/lib/financialStatement'

/**
 * Comparative financial statements.
 *
 * This page computes nothing. It used to: it read the general ledger itself,
 * grouped postable accounts by `account_type` in the browser and totalled them
 * here, which meant the comparative could disagree with the statement it was
 * supposed to be comparing. Every figure now comes from
 * `fn_comparative_financial_statement_report`, which calls the one governed
 * reporting entry point twice and presents both columns on the current account
 * mapping.
 */
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => `${new Date().getFullYear()}-01-01`

const STATEMENTS: { key: FsStatement; label: string; current: string; prior: string }[] = [
  { key: 'balance_sheet', label: 'Statement of Financial Position', current: 'As of', prior: 'Prior year' },
  { key: 'income_statement', label: 'Statement of Comprehensive Income', current: 'Current period', prior: 'Prior period' },
  { key: 'equity_statement', label: 'Statement of Changes in Equity', current: 'Closing', prior: 'Prior closing' },
  { key: 'cash_flow', label: 'Statement of Cash Flows', current: 'Current period', prior: 'Prior period' },
]

export default function ComparativeFinancialStatementsPage() {
  const { companyId } = useAppCtx()
  const [statement, setStatement] = useState<FsStatement>('income_statement')
  const [periodStart, setPeriodStart] = useState(firstOfYear())
  const [periodEnd, setPeriodEnd] = useState(today())
  const [showNotes, setShowNotes] = useState(true)

  const { period, loading: resolving } = useComparativePeriod(companyId, periodStart, periodEnd)
  const priorStart = period?.available ? period.prior_period_start : null
  const priorEnd = period?.available ? period.prior_period_end : null

  const { lines, loading, error } = useComparativeFinancialStatement(
    companyId, statement, periodStart, periodEnd, priorStart, priorEnd)
  const { notes } = useFinancialStatementNotes(companyId, periodStart, periodEnd, priorStart, priorEnd)

  const active = STATEMENTS.find(s => s.key === statement)!
  const currentLabel = `${active.current} ${periodEnd}`
  const priorLabel = priorEnd ? `${active.prior} ${priorEnd}` : active.prior

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Comparative Financial Statements</h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Current period and prior comparable period, from the company's governed statement structure
          </p>
        </div>
        <button onClick={() => window.print()}
          className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={statement} onChange={e => setStatement(e.target.value as FsStatement)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {STATEMENTS.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}
        </select>
        <span className="text-xs text-gray-400">From</span>
        <input type="date" value={periodStart} onChange={e => setPeriodStart(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={periodEnd} onChange={e => setPeriodEnd(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <label className="flex items-center gap-1.5 text-xs text-gray-600 ml-auto">
          <input type="checkbox" checked={showNotes} onChange={e => setShowNotes(e.target.checked)}
            className="rounded border-gray-300" />
          Show notes
        </label>
      </div>

      {/* The comparative period is resolved from the company's fiscal calendar,
          not guessed from the browser's clock. When there isn't one, say so. */}
      {period && (
        <div className={`border rounded-lg px-4 py-2.5 text-sm ${period.available ? 'border-gray-200 bg-white text-gray-600' : 'border-amber-200 bg-amber-50 text-amber-800'}`}>
          {period.available ? (
            <>
              <span className="font-medium text-gray-800">Comparative:</span>{' '}
              {period.prior_period_start} to {period.prior_period_end}
              {period.prior_fiscal_year_name && <> — {period.prior_fiscal_year_name}</>}
              {period.prior_year_closed
                ? <span className="ml-2 text-[10px] uppercase tracking-wide text-gray-500">closed books</span>
                : <span className="ml-2 text-[10px] uppercase tracking-wide text-amber-700">year still open</span>}
              {period.prior_has_activity === false && (
                <span className="ml-2 text-xs text-amber-700">no transactions were posted in the comparative period</span>
              )}
            </>
          ) : (
            <>
              <span className="font-medium">No comparative period.</span> {period.reason}
            </>
          )}
        </div>
      )}

      {error && (
        <div className="border border-red-200 bg-red-50 text-red-700 rounded-lg px-4 py-3 text-sm">{error}</div>
      )}

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">
          Select a company from the context bar above.
        </div>
      ) : resolving || loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : !period?.available ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">
          A comparative statement needs a prior comparable period. Report a period inside a fiscal
          year that has one before it.
        </div>
      ) : (
        <ComparativeStatementTable
          lines={lines}
          currentLabel={currentLabel}
          priorLabel={priorLabel}
          emptyMessage="No governed statement lines are mapped for this company."
          companyId={companyId}
          statement={statement}
          periodStart={periodStart} periodEnd={periodEnd}
          priorStart={priorStart!} priorEnd={priorEnd!}
        />
      )}

      <p className="text-xs text-gray-500">
        {statement === 'balance_sheet' || statement === 'equity_statement'
          ? 'Balances are compared as of each period end.'
          : 'Movements are compared for each period.'}{' '}
        Closing journals are excluded from comprehensive income and cash flows and included in the
        position and in changes in equity, so a closed year still reports the revenue it earned.
        Select any line to see the accounts behind it, and any account to open its ledger.
      </p>

      {showNotes && companyId && <StatementNotes notes={notes} />}
    </div>
  )
}
