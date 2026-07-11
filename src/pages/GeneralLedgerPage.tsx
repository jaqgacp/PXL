import { useState, useEffect, useCallback } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { ArrowLeft, BookOpen, Route } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COARef = { id: string; account_code: string; account_name: string; normal_balance: string }
type GLRow = {
  line_id: string; je_id: string; account_id: string; je_date: string; je_number: string
  je_description: string | null; reference_doc_type: string | null
  line_description: string | null; debit_amount: number; credit_amount: number
  account_code: string; account_name: string; normal_balance: string
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function GeneralLedgerPage() {
  const { companyId } = useAppCtx()
  const [searchParams] = useSearchParams()
  const requestedJeId = searchParams.get('jeId') || ''
  const requestedAccountId = searchParams.get('accountId') || searchParams.get('account') || ''
  const [accounts, setAccounts] = useState<COARef[]>([])
  const [accountId, setAccountId] = useState(requestedAccountId)
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())

  const [rows, setRows] = useState<GLRow[]>([])
  const [opening, setOpening] = useState(0)
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)
  const [jeRows, setJeRows] = useState<GLRow[]>([])
  const [jeLoading, setJeLoading] = useState(false)
  const [jeError, setJeError] = useState('')
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

  const loadAccountLedger = useCallback(async (targetAccountId: string) => {
    if (!companyId || !targetAccountId || !dateFrom || !dateTo) return
    setLoading(true)
    const [movRes, openRes] = await Promise.all([
      supabase.from('vw_general_ledger').select('*')
        .eq('company_id', companyId).eq('account_id', targetAccountId)
        .gte('je_date', dateFrom).lte('je_date', dateTo)
        .order('je_date', { ascending: true }).order('je_number', { ascending: true }),
      supabase.from('vw_general_ledger').select('debit_amount,credit_amount')
        .eq('company_id', companyId).eq('account_id', targetAccountId).lt('je_date', dateFrom),
    ])
    setRows((movRes.data as GLRow[]) || [])
    const op = ((openRes.data as any[]) || []).reduce((s, r) => s + Number(r.debit_amount) - Number(r.credit_amount), 0)
    // opening expressed in the account's normal direction
    const selectedAccount = accounts.find(item => item.id === targetAccountId)
    setOpening(selectedAccount?.normal_balance === 'credit' ? -op : op)
    setApplied(true)
    setLoading(false)
  }, [accounts, companyId, dateFrom, dateTo])

  const apply = () => { void loadAccountLedger(accountId) }

  useEffect(() => {
    if (!requestedAccountId || !companyId || !accounts.some(item => item.id === requestedAccountId)) return
    const key = `${companyId}:${requestedAccountId}`
    if (autoAppliedKey === key) return
    setAccountId(requestedAccountId)
    setAutoAppliedKey(key)
    void loadAccountLedger(requestedAccountId)
  }, [accounts, autoAppliedKey, companyId, dateFrom, dateTo, loadAccountLedger, requestedAccountId])

  useEffect(() => {
    if (!companyId || !requestedJeId) {
      setJeRows([])
      setJeError('')
      return
    }
    let alive = true
    const loadJournalSlice = async () => {
      setJeLoading(true)
      setJeError('')
      const { data, error } = await supabase.from('vw_general_ledger').select('*')
        .eq('company_id', companyId)
        .eq('je_id', requestedJeId)
        .order('line_id')
      if (!alive) return
      setJeRows((data as GLRow[]) || [])
      setJeError(error?.message || (!data?.length ? 'No posted GL lines were found for this journal entry.' : ''))
      setJeLoading(false)
    }
    void loadJournalSlice()
    return () => { alive = false }
  }, [companyId, requestedJeId])

  // running balance in normal direction
  const isCredit = account?.normal_balance === 'credit'
  let running = opening
  const computed = rows.map(r => {
    const delta = isCredit ? (r.credit_amount - r.debit_amount) : (r.debit_amount - r.credit_amount)
    running += delta
    return { ...r, running }
  })
  const periodDebit = rows.reduce((s, r) => s + r.debit_amount, 0)
  const periodCredit = rows.reduce((s, r) => s + r.credit_amount, 0)
  const closing = running

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

  if (requestedJeId) {
    const targetDebit = jeRows.reduce((sum, row) => sum + Number(row.debit_amount), 0)
    const targetCredit = jeRows.reduce((sum, row) => sum + Number(row.credit_amount), 0)
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">General Ledger</span>
          <span className="text-xs text-gray-500 font-mono">JE {requestedJeId.slice(0, 8)}</span>
          <Link to="/general-ledger" className="ml-auto inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900">
            <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
            All account activity
          </Link>
        </div>
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
            {jeLoading ? (
              <div className="py-12 text-center text-sm text-gray-400">Loading journal entry lines...</div>
            ) : jeError ? (
              <div className="m-4 border border-amber-200 bg-amber-50 rounded-md px-4 py-3 text-sm text-amber-800">{jeError}</div>
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
                  {jeRows.map(row => (
                    <tr key={row.line_id}>
                      <td className="px-3 py-2 font-mono text-gray-500">{row.je_date}</td>
                      <td className="px-3 py-2 font-mono font-semibold">
                        <Link to={`/accounting-trace?jeId=${row.je_id}`} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                          {row.je_number}
                          <Route className="h-3 w-3" aria-hidden="true" />
                        </Link>
                      </td>
                      <td className="px-3 py-2">
                        <Link to={`/account-detail-ledger?accountId=${row.account_id}`} className="font-medium text-blue-700 hover:text-blue-900">
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
          <button onClick={exportCSV} className="ml-auto px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Export CSV</button>
        )}
      </div>

      {!applied ? (
        <div className="py-20 text-center text-sm text-gray-400">Select an account and date range, then Apply.</div>
      ) : (
        <div className="px-5 py-4">
          {account && (
            <div className="mb-3 flex items-baseline gap-3">
              <Link to={`/account-detail-ledger?accountId=${account.id}`}
                className="inline-flex items-center gap-1.5 text-base font-semibold text-blue-700 hover:text-blue-900 font-mono">
                {account.account_code} — {account.account_name}
                <BookOpen className="h-4 w-4" aria-hidden="true" />
              </Link>
              <span className="text-xs text-gray-500 uppercase">Normal balance: {account.normal_balance}</span>
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
