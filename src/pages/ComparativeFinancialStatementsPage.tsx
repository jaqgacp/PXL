import { Fragment, useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COA = { id: string; account_code: string; account_name: string; account_type: string }
type GLAgg = { account_id: string; debit_amount: number; credit_amount: number }
type Line = { account_id: string; account_code: string; account_name: string; account_type: string; current: number; prior: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'
const firstOfLastYear = () => (new Date().getFullYear() - 1) + '-01-01'
const endOfLastYear = () => (new Date().getFullYear() - 1) + '-12-31'

export default function ComparativeFinancialStatementsPage() {
  const { companyId } = useAppCtx()
  const [reportType, setReportType] = useState<'income_statement' | 'balance_sheet'>('income_statement')
  const [curFrom, setCurFrom] = useState(firstOfYear())
  const [curTo, setCurTo] = useState(today())
  const [priorFrom, setPriorFrom] = useState(firstOfLastYear())
  const [priorTo, setPriorTo] = useState(endOfLastYear())
  const [lines, setLines] = useState<Line[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const types = reportType === 'income_statement' ? ['revenue', 'expense'] : ['asset', 'liability', 'equity']
    const isBalanceSheet = reportType === 'balance_sheet'

    const { data: accounts } = await supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type')
      .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).in('account_type', types).order('account_code')

    let curQuery = supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount').eq('company_id', companyId).lte('je_date', curTo)
    let priorQuery = supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount').eq('company_id', companyId).lte('je_date', priorTo)
    if (!isBalanceSheet) {
      curQuery = curQuery.gte('je_date', curFrom)
      priorQuery = priorQuery.gte('je_date', priorFrom)
    }
    const [{ data: curGl }, { data: priorGl }] = await Promise.all([curQuery, priorQuery])

    const aggregate = (rows: GLAgg[]) => {
      const m: Record<string, number> = {}
      for (const r of rows) m[r.account_id] = (m[r.account_id] || 0) + Number(r.debit_amount) - Number(r.credit_amount)
      return m
    }
    const curBal = aggregate((curGl as GLAgg[]) || [])
    const priorBal = aggregate((priorGl as GLAgg[]) || [])

    const result: Line[] = ((accounts as COA[]) || []).map(a => {
      let cur = curBal[a.id] || 0, prior = priorBal[a.id] || 0
      if (a.account_type === 'revenue') { cur = -cur; prior = -prior }
      else if (a.account_type === 'liability' || a.account_type === 'equity') { cur = -cur; prior = -prior }
      return { account_id: a.id, account_code: a.account_code, account_name: a.account_name, account_type: a.account_type, current: cur, prior }
    }).filter(l => Math.abs(l.current) >= 0.005 || Math.abs(l.prior) >= 0.005)

    setLines(result)
    setLoading(false)
  }, [companyId, reportType, curFrom, curTo, priorFrom, priorTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const groups = reportType === 'income_statement'
    ? [{ key: 'revenue', label: 'Revenue' }, { key: 'expense', label: 'Expenses' }]
    : [{ key: 'asset', label: 'Assets' }, { key: 'liability', label: 'Liabilities' }, { key: 'equity', label: 'Equity' }]

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Comparative Financial Statements</h1>
          <p className="text-sm text-gray-500 mt-0.5">Current period vs. prior period, side by side</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={reportType} onChange={e => setReportType(e.target.value as typeof reportType)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="income_statement">Income Statement</option>
          <option value="balance_sheet">Balance Sheet</option>
        </select>
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-500">Current:</span>
          {reportType === 'income_statement' && <input type="date" value={curFrom} onChange={e => setCurFrom(e.target.value)} className="border border-gray-300 rounded-md px-2 py-1.5 text-sm" />}
          <input type="date" value={curTo} onChange={e => setCurTo(e.target.value)} className="border border-gray-300 rounded-md px-2 py-1.5 text-sm" />
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-500">Prior:</span>
          {reportType === 'income_statement' && <input type="date" value={priorFrom} onChange={e => setPriorFrom(e.target.value)} className="border border-gray-300 rounded-md px-2 py-1.5 text-sm" />}
          <input type="date" value={priorTo} onChange={e => setPriorTo(e.target.value)} className="border border-gray-300 rounded-md px-2 py-1.5 text-sm" />
        </div>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Account</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Current</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Prior</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Variance</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">% Change</th>
              </tr>
            </thead>
            <tbody>
              {groups.map(g => {
                const groupLines = lines.filter(l => l.account_type === g.key)
                if (groupLines.length === 0) return null
                const groupCur = groupLines.reduce((s, l) => s + l.current, 0)
                const groupPrior = groupLines.reduce((s, l) => s + l.prior, 0)
                return (
                  <Fragment key={g.key}>
                    <tr className="bg-gray-50/70"><td colSpan={5} className="px-4 py-1.5 text-xs font-semibold text-gray-500 uppercase">{g.label}</td></tr>
                    {groupLines.map(l => {
                      const variance = l.current - l.prior
                      const pctChange = l.prior !== 0 ? (variance / Math.abs(l.prior)) * 100 : 0
                      return (
                        <tr key={l.account_code} className="border-b border-gray-100 hover:bg-gray-50">
                          <td className="px-4 py-1.5 text-gray-700">{l.account_code} — {l.account_name}</td>
                          <td className="px-4 py-1.5 text-right font-mono tabular-nums">
                            <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${curFrom}&dateTo=${curTo}`} className="text-blue-700 hover:text-blue-900">
                              {fmt(l.current)}
                            </Link>
                          </td>
                          <td className="px-4 py-1.5 text-right font-mono tabular-nums">
                            <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${priorFrom}&dateTo=${priorTo}`} className="text-blue-600 hover:text-blue-900">
                              {fmt(l.prior)}
                            </Link>
                          </td>
                          <td className={`px-4 py-1.5 text-right font-mono tabular-nums ${variance >= 0 ? 'text-green-600' : 'text-red-600'}`}>{fmt(variance)}</td>
                          <td className={`px-4 py-1.5 text-right font-mono tabular-nums text-xs ${pctChange >= 0 ? 'text-green-600' : 'text-red-600'}`}>{l.prior !== 0 ? `${pctChange.toFixed(1)}%` : '—'}</td>
                        </tr>
                      )
                    })}
                    <tr className="border-b-2 border-gray-300 bg-gray-50">
                      <td className="px-4 py-1.5 text-sm font-semibold text-gray-900">Total {g.label}</td>
                      <td className="px-4 py-1.5 text-right font-mono text-sm font-semibold tabular-nums text-gray-900">{fmt(groupCur)}</td>
                      <td className="px-4 py-1.5 text-right font-mono text-sm font-semibold tabular-nums text-gray-600">{fmt(groupPrior)}</td>
                      <td colSpan={2} />
                    </tr>
                  </Fragment>
                )
              })}
              {lines.length === 0 && <tr><td colSpan={5} className="text-center py-16 text-gray-400">No data for the selected periods.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
