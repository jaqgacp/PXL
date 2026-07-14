import { useState, useEffect, useCallback, useMemo } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { ArrowLeft, BookOpen, Route } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COARef = { id: string; account_code: string; account_name: string; normal_balance: string }
type GLRow = {
  line_id: string; je_id: string; account_id: string; je_date: string; je_number: string
  je_description: string | null; reference_doc_type: string | null; reference_doc_id: string | null
  line_description: string | null; debit_amount: number; credit_amount: number
  account_code: string; account_name: string; account_type: string; normal_balance: string
  branch_id: string | null; department_id: string | null; cost_center_id: string | null
  running_balance?: number; total_rows?: number; period_debit?: number; period_credit?: number
}
type LedgerSummary = { totalRows: number; periodDebit: number; periodCredit: number; closing: number }

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'
const PAGE_SIZE = 200

export default function GeneralLedgerPage() {
  const { companyId } = useAppCtx()
  const [searchParams] = useSearchParams()
  const requestedJeId = searchParams.get('jeId') || ''
  const requestedAccountId = searchParams.get('accountId') || searchParams.get('account') || ''
  const requestedDateFrom = searchParams.get('dateFrom') || ''
  const requestedDateTo = searchParams.get('dateTo') || ''
  const requestedSourceType = (searchParams.get('sourceType') || '').trim().toUpperCase()
  const requestedSourceId = searchParams.get('sourceId') || ''
  const requestedAccountTypeParam = searchParams.get('accountType') || ''
  const requestedAccountTypes = useMemo(
    () => requestedAccountTypeParam.split(',').map(value => value.trim()).filter(Boolean),
    [requestedAccountTypeParam],
  )
  const requestedBranchId = searchParams.get('branchId') || ''
  const requestedDepartmentId = searchParams.get('departmentId') || ''
  const requestedCostCenterId = searchParams.get('costCenterId') || ''
  const hasFocusedFilter = Boolean(
    requestedJeId || requestedSourceType || requestedSourceId || requestedAccountTypes.length
    || requestedBranchId || requestedDepartmentId || requestedCostCenterId,
  )
  const [accounts, setAccounts] = useState<COARef[]>([])
  const [accountId, setAccountId] = useState(requestedAccountId)
  const [dateFrom, setDateFrom] = useState(requestedDateFrom || firstOfYear())
  const [dateTo, setDateTo] = useState(requestedDateTo || today())

  const [rows, setRows] = useState<GLRow[]>([])
  const [opening, setOpening] = useState(0)
  const [ledgerSummary, setLedgerSummary] = useState<LedgerSummary>({ totalRows: 0, periodDebit: 0, periodCredit: 0, closing: 0 })
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)
  const [focusedRows, setFocusedRows] = useState<GLRow[]>([])
  const [focusedPage, setFocusedPage] = useState(0)
  const [focusedTotalRows, setFocusedTotalRows] = useState(0)
  const [focusedDebit, setFocusedDebit] = useState(0)
  const [focusedCredit, setFocusedCredit] = useState(0)
  const [focusedLoading, setFocusedLoading] = useState(false)
  const [focusedError, setFocusedError] = useState('')
  const [autoAppliedKey, setAutoAppliedKey] = useState('')

  const loadAccounts = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('chart_of_accounts')
      .select('id,account_code,account_name,normal_balance')
      .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code')
    setAccounts((data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) loadAccounts() }, [loadAccounts, companyId])

  const account = accounts.find(a => a.id === accountId)

  const loadAccountLedger = useCallback(async (targetAccountId: string, targetPage = 0) => {
    if (!companyId || !targetAccountId || !dateFrom || !dateTo) return
    setLoading(true)
    const [movRes, summaryRes] = await Promise.all([
      supabase.rpc('fn_gl_account_ledger_page', {
        p_company_id: companyId,
        p_account_id: targetAccountId,
        p_date_from: dateFrom,
        p_date_to: dateTo,
        p_je_id: undefined,
        p_limit: PAGE_SIZE,
        p_offset: targetPage * PAGE_SIZE,
      }),
      supabase.rpc('fn_gl_account_ledger_summary', {
        p_company_id: companyId,
        p_account_id: targetAccountId,
        p_date_from: dateFrom,
        p_date_to: dateTo,
        p_je_id: undefined,
      }),
    ])
    const summary = ((summaryRes.data as any[]) || [])[0]
    setRows((movRes.data as GLRow[]) || [])
    setOpening(Number(summary?.opening_balance || 0))
    setLedgerSummary({
      totalRows: Number(summary?.total_rows || 0),
      periodDebit: Number(summary?.period_debit || 0),
      periodCredit: Number(summary?.period_credit || 0),
      closing: Number(summary?.closing_balance || 0),
    })
    setPage(targetPage)
    setApplied(true)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  const apply = () => { void loadAccountLedger(accountId, 0) }

  useEffect(() => {
    if (hasFocusedFilter) return
    if (!requestedAccountId || !companyId || !accounts.some(item => item.id === requestedAccountId)) return
    const key = `${companyId}:${requestedAccountId}:${dateFrom}:${dateTo}`
    if (autoAppliedKey === key) return
    setAccountId(requestedAccountId)
    setAutoAppliedKey(key)
    void loadAccountLedger(requestedAccountId, 0)
  }, [accounts, autoAppliedKey, companyId, dateFrom, dateTo, hasFocusedFilter, loadAccountLedger, requestedAccountId])

  useEffect(() => {
    if (!companyId || !hasFocusedFilter) {
      setFocusedRows([])
      setFocusedError('')
      return
    }
    let alive = true
    const loadFocusedSlice = async () => {
      setFocusedLoading(true)
      setFocusedError('')
      const { data, error } = await supabase.rpc('fn_general_ledger_report', {
        p_company_id: companyId,
        p_date_from: requestedDateFrom || undefined,
        p_date_to: requestedDateTo || undefined,
        p_account_id: requestedAccountId || undefined,
        p_je_id: requestedJeId || undefined,
        p_reference_doc_type: requestedSourceType || undefined,
        p_reference_doc_id: requestedSourceId || undefined,
        p_account_types: requestedAccountTypes.length ? requestedAccountTypes : undefined,
        p_branch_id: requestedBranchId || undefined,
        p_department_id: requestedDepartmentId || undefined,
        p_cost_center_id: requestedCostCenterId || undefined,
        p_entry_classes: undefined,
        p_limit: PAGE_SIZE,
        p_offset: focusedPage * PAGE_SIZE,
      })
      if (!alive) return
      const nextRows = (data as GLRow[]) || []
      const first = nextRows[0]
      setFocusedRows(nextRows)
      setFocusedTotalRows(Number(first?.total_rows || 0))
      setFocusedDebit(Number(first?.period_debit || 0))
      setFocusedCredit(Number(first?.period_credit || 0))
      setFocusedError(error?.message || (!nextRows.length ? 'No posted GL lines were found for these filters.' : ''))
      setFocusedLoading(false)
    }
    void loadFocusedSlice()
    return () => { alive = false }
  }, [companyId, focusedPage, hasFocusedFilter, requestedAccountId, requestedAccountTypes, requestedBranchId, requestedCostCenterId, requestedDateFrom, requestedDateTo, requestedDepartmentId, requestedJeId, requestedSourceId, requestedSourceType])

  const computed = rows.map(r => ({ ...r, running: Number(r.running_balance || 0) }))
  const periodDebit = ledgerSummary.periodDebit
  const periodCredit = ledgerSummary.periodCredit
  const closing = ledgerSummary.closing
  const pageCount = Math.max(1, Math.ceil(ledgerSummary.totalRows / PAGE_SIZE))
  const focusedPageCount = Math.max(1, Math.ceil(focusedTotalRows / PAGE_SIZE))

  const exportCSV = () => {
    const header = ['Date', 'JE Number', 'Description', 'Ref Type', 'Line Description', 'Debit', 'Credit', 'Running Balance']
    const lines = [header.join(',')]
    lines.push(['', '', 'Opening Balance', '', '', '', '', opening.toFixed(2)].join(','))
    for (const r of computed) {
      lines.push([r.je_date, r.je_number, `"${(r.je_description || '').replace(/"/g, '""')}"`, r.reference_doc_type || '',
        `"${(r.line_description || '').replace(/"/g, '""')}"`, r.debit_amount.toFixed(2), r.credit_amount.toFixed(2), r.running.toFixed(2)].join(','))
    }
    lines.push(['', '', 'Closing Balance', '', '', periodDebit.toFixed(2), periodCredit.toFixed(2), closing.toFixed(2)].join(','))
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `GL_${account?.account_code || 'account'}_${dateFrom}_${dateTo}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  if (hasFocusedFilter) {
    const targetDebit = focusedDebit
    const targetCredit = focusedCredit
    const focusedLabel = requestedJeId
      ? `JE ${requestedJeId.slice(0, 8)}`
      : requestedSourceType || requestedSourceId
        ? `${requestedSourceType || 'Source'}${requestedSourceId ? ` ${requestedSourceId.slice(0, 8)}` : ''}`
        : 'Report drilldown'
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">General Ledger</span>
          <span className="text-xs text-gray-500 font-mono">{focusedLabel}</span>
          {(requestedDateFrom || requestedDateTo) && (
            <span className="text-xs text-gray-400">{requestedDateFrom || 'Beginning'} to {requestedDateTo || 'Today'}</span>
          )}
          <Link to="/general-ledger" className="ml-auto inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900">
            <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
            All account activity
          </Link>
        </div>
        <div className="px-5 py-4">
          {focusedTotalRows > PAGE_SIZE && (
            <div className="mb-3 flex items-center justify-end gap-2 text-xs text-gray-500">
              <span>Rows {focusedPage * PAGE_SIZE + 1}-{Math.min((focusedPage + 1) * PAGE_SIZE, focusedTotalRows)} of {focusedTotalRows}</span>
              <button onClick={() => setFocusedPage(page => Math.max(0, page - 1))} disabled={focusedPage === 0 || focusedLoading}
                className="px-2 py-1 border border-gray-300 rounded disabled:opacity-40">Previous</button>
              <button onClick={() => setFocusedPage(page => Math.min(focusedPageCount - 1, page + 1))} disabled={focusedPage >= focusedPageCount - 1 || focusedLoading}
                className="px-2 py-1 border border-gray-300 rounded disabled:opacity-40">Next</button>
            </div>
          )}
          <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
            {focusedLoading ? (
              <div className="py-12 text-center text-sm text-gray-400">Loading general ledger lines...</div>
            ) : focusedError ? (
              <div className="m-4 border border-amber-200 bg-amber-50 rounded-md px-4 py-3 text-sm text-amber-800">{focusedError}</div>
            ) : (
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date', 'JE Number', 'Account', 'Description', 'Debit', 'Credit'].map(header => (
                      <th key={header} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Debit', 'Credit'].includes(header) ? 'text-right' : 'text-left'}`}>{header}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {focusedRows.map(row => (
                    <tr key={row.line_id}>
                      <td className="px-3 py-2 font-mono text-gray-500">{row.je_date}</td>
                      <td className="px-3 py-2 font-mono font-semibold">
                        <Link to={`/accounting-trace?jeId=${row.je_id}`} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                          {row.je_number}
                          <Route className="h-3 w-3" aria-hidden="true" />
                        </Link>
                      </td>
                      <td className="px-3 py-2">
                        <Link to={`/account-detail-ledger?accountId=${row.account_id}&jeId=${row.je_id}&dateFrom=${row.je_date}&dateTo=${row.je_date}`} className="font-medium text-blue-700 hover:text-blue-900">
                          {row.account_code} - {row.account_name}
                        </Link>
                      </td>
                      <td className="px-3 py-2 text-gray-500">{row.line_description || row.je_description || '-'}</td>
                      <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{row.debit_amount ? fmt(row.debit_amount) : '-'}</td>
                      <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{row.credit_amount ? fmt(row.credit_amount) : '-'}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t border-gray-200 bg-gray-50">
                  <tr>
                    <td colSpan={4} className="px-3 py-2 text-right font-semibold text-gray-700">Totals</td>
                    <td className="px-3 py-2 text-right font-mono font-bold text-gray-900">{fmt(targetDebit)}</td>
                    <td className="px-3 py-2 text-right font-mono font-bold text-gray-900">{fmt(targetCredit)}</td>
                  </tr>
                </tfoot>
              </table>
            )}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">General Ledger</span>
        <select value={accountId} onChange={e => setAccountId(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-72 focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">— select account —</option>
          {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
        </select>
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} title="From"
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} title="To"
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <button onClick={apply} disabled={!accountId || loading}
          className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
          {loading ? 'Loading…' : 'Apply'}
        </button>
        {applied && computed.length > 0 && (
          <button onClick={exportCSV} className="ml-auto px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Export Page CSV</button>
        )}
      </div>

      {!applied ? (
        <div className="py-20 text-center text-sm text-gray-400">Select an account and date range, then Apply.</div>
      ) : (
        <div className="px-5 py-4">
          {account && (
            <div className="mb-3 flex items-baseline gap-3">
              <Link to={`/account-detail-ledger?accountId=${account.id}&dateFrom=${dateFrom}&dateTo=${dateTo}`}
                className="inline-flex items-center gap-1.5 text-base font-semibold text-blue-700 hover:text-blue-900 font-mono">
                {account.account_code} — {account.account_name}
                <BookOpen className="h-4 w-4" aria-hidden="true" />
              </Link>
              <span className="text-xs text-gray-500 uppercase">Normal balance: {account.normal_balance}</span>
            </div>
          )}
          {ledgerSummary.totalRows > PAGE_SIZE && (
            <div className="mb-3 flex items-center justify-end gap-2 text-xs text-gray-500">
              <span>Rows {page * PAGE_SIZE + 1}-{Math.min((page + 1) * PAGE_SIZE, ledgerSummary.totalRows)} of {ledgerSummary.totalRows}</span>
              <button onClick={() => void loadAccountLedger(accountId, Math.max(0, page - 1))} disabled={page === 0 || loading}
                className="px-2 py-1 border border-gray-300 rounded disabled:opacity-40">Previous</button>
              <button onClick={() => void loadAccountLedger(accountId, Math.min(pageCount - 1, page + 1))} disabled={page >= pageCount - 1 || loading}
                className="px-2 py-1 border border-gray-300 rounded disabled:opacity-40">Next</button>
            </div>
          )}
          <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Date', 'JE Number', 'Description', 'Ref Type', 'Line Description', 'Debit', 'Credit', 'Running Balance'].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Debit', 'Credit', 'Running Balance'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                <tr className="bg-gray-50/60 italic text-gray-500">
                  <td className="px-3 py-2" colSpan={5}>Opening Balance</td>
                  <td className="px-3 py-2 text-right">—</td>
                  <td className="px-3 py-2 text-right">—</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums">{fmt(opening)}</td>
                </tr>
                {computed.map(r => (
                  <tr key={r.line_id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono text-gray-500">{r.je_date}</td>
                    <td className="px-3 py-2 font-mono font-semibold">
                      <Link to={`/accounting-trace?jeId=${r.je_id}`} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                        {r.je_number}
                        <Route className="h-3 w-3" aria-hidden="true" />
                      </Link>
                    </td>
                    <td className="px-3 py-2 text-gray-700 max-w-[200px] truncate">{r.je_description || '—'}</td>
                    <td className="px-3 py-2 text-gray-500">{r.reference_doc_type || '—'}</td>
                    <td className="px-3 py-2 text-gray-500 max-w-[180px] truncate">{r.line_description || '—'}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{r.debit_amount ? fmt(r.debit_amount) : '—'}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{r.credit_amount ? fmt(r.credit_amount) : '—'}</td>
                    <td className={`px-3 py-2 text-right font-mono tabular-nums font-medium ${r.running >= 0 ? 'text-green-700' : 'text-red-600'}`}>{fmt(r.running)}</td>
                  </tr>
                ))}
                {computed.length === 0 && (
                  <tr><td colSpan={8} className="px-3 py-8 text-center text-gray-400">No postings in this date range.</td></tr>
                )}
              </tbody>
              <tfoot className="border-t border-gray-200 bg-gray-50">
                <tr>
                  <td className="px-3 py-2 text-right font-semibold text-gray-700" colSpan={5}>Period Totals / Closing Balance</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(periodDebit)}</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(periodCredit)}</td>
                  <td className={`px-3 py-2 text-right font-mono tabular-nums font-bold ${closing >= 0 ? 'text-green-700' : 'text-red-600'}`}>{fmt(closing)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
