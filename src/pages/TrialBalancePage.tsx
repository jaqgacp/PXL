import { Fragment, useState, useEffect, useCallback } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { BookOpen, Scale } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COA = { id: string; account_code: string; account_name: string; account_type: string; normal_balance: string }
type PeriodRef = { id: string; period_name: string; start_date: string; end_date: string }
type GLAgg = { account_id: string; debit_amount: number; credit_amount: number }

type TBRow = {
  id: string; account_code: string; account_name: string; account_type: string
  openingNet: number; periodDebit: number; periodCredit: number; closingNet: number
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

const TYPE_ORDER = ['asset', 'liability', 'equity', 'revenue', 'expense']
const TYPE_LABEL: Record<string, string> = {
  asset: 'Assets', liability: 'Liabilities', equity: 'Equity', revenue: 'Revenue', expense: 'Expenses',
}

export default function TrialBalancePage() {
  const { companyId } = useAppCtx()
  const [searchParams] = useSearchParams()
  const requestedAccountId = searchParams.get('accountId') || searchParams.get('account') || ''
  const [accounts, setAccounts] = useState<COA[]>([])
  const [periods, setPeriods] = useState<PeriodRef[]>([])

  const [useRange, setUseRange] = useState(false)
  const [periodId, setPeriodId] = useState('')
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [includeZero, setIncludeZero] = useState(false)
  const [adjusted, setAdjusted] = useState(false)

  const [rows, setRows] = useState<TBRow[]>([])
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [coaRes, perRes] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type,normal_balance')
        .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
      supabase.from('fiscal_periods').select('id,period_name,start_date,end_date')
        .eq('company_id', companyId).order('start_date', { ascending: false }),
    ])
    setAccounts((coaRes.data as COA[]) || [])
    const per = (perRes.data as PeriodRef[]) || []
    setPeriods(per)
    if (per.length && !periodId) setPeriodId(per[0].id)
  }, [companyId, periodId])

  useEffect(() => { if (companyId) loadRefs() }, [loadRefs, companyId])

  const aggregate = (gl: GLAgg[]): Record<string, { d: number; c: number }> => {
    const m: Record<string, { d: number; c: number }> = {}
    for (const r of gl) {
      if (!m[r.account_id]) m[r.account_id] = { d: 0, c: 0 }
      m[r.account_id].d += Number(r.debit_amount)
      m[r.account_id].c += Number(r.credit_amount)
    }
    return m
  }

  const apply = async () => {
    if (!companyId) return
    let start = dateFrom, end = dateTo
    if (!useRange) {
      const p = periods.find(x => x.id === periodId)
      if (!p) return
      start = p.start_date; end = p.end_date
    }
    setLoading(true)
    const [movRes, openRes] = await Promise.all([
      supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount')
        .eq('company_id', companyId).gte('je_date', start).lte('je_date', end),
      supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount')
        .eq('company_id', companyId).lt('je_date', start),
    ])
    const mov = aggregate((movRes.data as GLAgg[]) || [])
    const open = aggregate((openRes.data as GLAgg[]) || [])

    const result: TBRow[] = accounts.map(a => {
      const o = open[a.id] || { d: 0, c: 0 }
      const m = mov[a.id] || { d: 0, c: 0 }
      const openingNet = o.d - o.c
      const closingNet = openingNet + (m.d - m.c)
      return {
        id: a.id, account_code: a.account_code, account_name: a.account_name, account_type: a.account_type,
        openingNet, periodDebit: m.d, periodCredit: m.c, closingNet,
      }
    })
    setRows(result)
    setApplied(true)
    setLoading(false)
  }

  const visible = rows.filter(r => {
    if (requestedAccountId && r.id !== requestedAccountId) return false
    const nonZero = Math.abs(r.openingNet) > 0.005 || r.periodDebit > 0.005 || r.periodCredit > 0.005 || Math.abs(r.closingNet) > 0.005
    if (adjusted) return Math.abs(r.closingNet) > 0.005
    if (!includeZero) return nonZero
    return true
  })

  const grandClosingDebit = visible.reduce((s, r) => s + (r.closingNet > 0 ? r.closingNet : 0), 0)
  const grandClosingCredit = visible.reduce((s, r) => s + (r.closingNet < 0 ? -r.closingNet : 0), 0)
  const balanced = Math.abs(grandClosingDebit - grandClosingCredit) <= 0.01

  const exportCSV = () => {
    const header = ['Account Code', 'Account Name', 'Type', 'Opening Debit', 'Opening Credit', 'Period Debit', 'Period Credit', 'Closing Debit', 'Closing Credit']
    const lines = [header.join(',')]
    for (const r of visible) {
      lines.push([r.account_code, `"${r.account_name.replace(/"/g, '""')}"`, r.account_type,
        (r.openingNet > 0 ? r.openingNet : 0).toFixed(2), (r.openingNet < 0 ? -r.openingNet : 0).toFixed(2),
        r.periodDebit.toFixed(2), r.periodCredit.toFixed(2),
        (r.closingNet > 0 ? r.closingNet : 0).toFixed(2), (r.closingNet < 0 ? -r.closingNet : 0).toFixed(2)].join(','))
    }
    lines.push(['', 'GRAND TOTAL', '', '', '', '', '', grandClosingDebit.toFixed(2), grandClosingCredit.toFixed(2)].join(','))
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `TrialBalance_${today()}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  const grouped = TYPE_ORDER.map(t => ({ type: t, items: visible.filter(r => r.account_type === t) })).filter(g => g.items.length > 0)

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Trial Balance</span>
        {requestedAccountId && (
          <Link to="/trial-balance" className="text-xs font-medium text-blue-700 hover:text-blue-900">Clear account filter</Link>
        )}
        <div className="flex rounded border border-gray-300 overflow-hidden">
          <button onClick={() => setUseRange(false)} className={`px-3 py-1.5 text-xs font-medium ${!useRange ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>By Period</button>
          <button onClick={() => setUseRange(true)} className={`px-3 py-1.5 text-xs font-medium border-l border-gray-300 ${useRange ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>By Date Range</button>
        </div>
        {!useRange ? (
          <select value={periodId} onChange={e => setPeriodId(e.target.value)}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            {periods.map(p => <option key={p.id} value={p.id}>{p.period_name}</option>)}
          </select>
        ) : (
          <>
            <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} title="From"
              className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
            <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} title="To"
              className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </>
        )}
        <label className="flex items-center gap-1.5 text-xs text-gray-600">
          <input type="checkbox" checked={includeZero} onChange={e => setIncludeZero(e.target.checked)} /> Include zero-balance
        </label>
        <label className="flex items-center gap-1.5 text-xs text-gray-600">
          <input type="checkbox" checked={adjusted} onChange={e => setAdjusted(e.target.checked)} /> Adjusted TB
        </label>
        <button onClick={apply} disabled={loading}
          className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
          {loading ? 'Loading…' : 'Apply'}
        </button>
        {applied && visible.length > 0 && (
          <button onClick={exportCSV} className="ml-auto px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Export CSV</button>
        )}
      </div>

      {!applied ? (
        <div className="py-20 text-center text-sm text-gray-400">Choose a period or date range, then Apply.</div>
      ) : (
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Account Code', 'Account Name', 'Opening Debit', 'Opening Credit', 'Period Debit', 'Period Credit', 'Closing Debit', 'Closing Credit'].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${hh.includes('Debit') || hh.includes('Credit') ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {grouped.map(g => (
                  <Fragment key={g.type}>
                    <tr className="bg-gray-100">
                      <td colSpan={8} className="px-3 py-1.5 text-[10px] font-semibold uppercase tracking-widest text-gray-600">{TYPE_LABEL[g.type]}</td>
                    </tr>
                    {g.items.map(r => (
                      <tr key={r.id} className="hover:bg-gray-50/60">
                        <td className="px-3 py-2 font-mono font-semibold">
                          <Link to={`/account-detail-ledger?accountId=${r.id}`} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                            {r.account_code}
                            <BookOpen className="h-3 w-3" aria-hidden="true" />
                          </Link>
                        </td>
                        <td className="px-3 py-2 text-gray-700 max-w-[240px] truncate">
                          <Link to={`/general-ledger?accountId=${r.id}`} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                            {r.account_name}
                            <Scale className="h-3 w-3" aria-hidden="true" />
                          </Link>
                        </td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-600">{r.openingNet > 0 ? fmt(r.openingNet) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-600">{r.openingNet < 0 ? fmt(-r.openingNet) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{r.periodDebit ? fmt(r.periodDebit) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{r.periodCredit ? fmt(r.periodCredit) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums font-medium text-gray-900">{r.closingNet > 0 ? fmt(r.closingNet) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums font-medium text-gray-900">{r.closingNet < 0 ? fmt(-r.closingNet) : '—'}</td>
                      </tr>
                    ))}
                  </Fragment>
                ))}
                {visible.length === 0 && (
                  <tr><td colSpan={8} className="px-3 py-8 text-center text-gray-400">No account balances to display.</td></tr>
                )}
              </tbody>
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={6} className="px-3 py-2 text-right font-semibold text-gray-700">GRAND TOTAL</td>
                  <td className={`px-3 py-2 text-right font-mono tabular-nums font-bold ${balanced ? 'text-green-700' : 'text-red-600'}`}>{fmt(grandClosingDebit)}</td>
                  <td className={`px-3 py-2 text-right font-mono tabular-nums font-bold ${balanced ? 'text-green-700' : 'text-red-600'}`}>{fmt(grandClosingCredit)}</td>
                </tr>
                {!balanced && (
                  <tr><td colSpan={8} className="px-3 py-1.5 text-right text-xs text-red-600 font-medium">Trial balance does not tie — difference {fmt(grandClosingDebit - grandClosingCredit)}</td></tr>
                )}
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
