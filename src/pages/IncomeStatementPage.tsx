import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COA = { id: string; account_code: string; account_name: string; account_type: string }
type GLAgg = { account_id: string; debit_amount: number; credit_amount: number }
type Line = { account_id: string; account_code: string; account_name: string; amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function IncomeStatementPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [revenue, setRevenue] = useState<Line[]>([])
  const [expenses, setExpenses] = useState<Line[]>([])
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: accounts }, { data: glData }] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type')
        .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true)
        .in('account_type', ['revenue', 'expense']).order('account_code'),
      supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount')
        .eq('company_id', companyId).gte('je_date', dateFrom).lte('je_date', dateTo),
    ])

    const coaList = (accounts as COA[]) || []
    const balances: Record<string, number> = {}
    for (const r of (glData as GLAgg[]) || []) {
      balances[r.account_id] = (balances[r.account_id] || 0) + Number(r.debit_amount) - Number(r.credit_amount)
    }

    const revLines: Line[] = [], expLines: Line[] = []
    for (const a of coaList) {
      const net = balances[a.id] || 0
      if (Math.abs(net) < 0.005) continue
      if (a.account_type === 'revenue') revLines.push({ account_id: a.id, account_code: a.account_code, account_name: a.account_name, amount: -net })
      else expLines.push({ account_id: a.id, account_code: a.account_code, account_name: a.account_name, amount: net })
    }

    setRevenue(revLines.sort((a, b) => a.account_code.localeCompare(b.account_code)))
    setExpenses(expLines.sort((a, b) => a.account_code.localeCompare(b.account_code)))
    setApplied(true)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalRevenue = revenue.reduce((s, l) => s + l.amount, 0)
  const totalExpenses = expenses.reduce((s, l) => s + l.amount, 0)
  const netIncome = totalRevenue - totalExpenses

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Income Statement</h1>
          <p className="text-sm text-gray-500 mt-0.5">Statement of Comprehensive Income</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : applied && (
        <div className="max-w-3xl bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Revenue</h2></div>
          <table className="w-full text-sm">
            <tbody>
              {revenue.length === 0 ? <tr><td colSpan={3} className="px-4 py-8 text-center text-gray-400">No revenue in this period.</td></tr> : revenue.map(l => (
                <tr key={l.account_code} className="border-b border-gray-100">
                  <td className="px-4 py-1.5 text-gray-500 text-xs w-20">{l.account_code}</td>
                  <td className="px-4 py-1.5">
                    <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${dateFrom}&dateTo=${dateTo}`} className="text-blue-700 hover:text-blue-900">
                      {l.account_name}
                    </Link>
                  </td>
                  <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(l.amount)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t border-gray-300 bg-gray-50">
              <tr><td colSpan={2} className="px-4 py-2 text-sm font-semibold text-gray-900">Total Revenue</td><td className="px-4 py-2 text-right font-mono text-sm font-semibold tabular-nums text-gray-900">{fmt(totalRevenue)}</td></tr>
            </tfoot>
          </table>

          <div className="px-4 py-3 border-b border-t-4 border-t-gray-100 border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Expenses</h2></div>
          <table className="w-full text-sm">
            <tbody>
              {expenses.length === 0 ? <tr><td colSpan={3} className="px-4 py-8 text-center text-gray-400">No expenses in this period.</td></tr> : expenses.map(l => (
                <tr key={l.account_code} className="border-b border-gray-100">
                  <td className="px-4 py-1.5 text-gray-500 text-xs w-20">{l.account_code}</td>
                  <td className="px-4 py-1.5">
                    <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${dateFrom}&dateTo=${dateTo}`} className="text-blue-700 hover:text-blue-900">
                      {l.account_name}
                    </Link>
                  </td>
                  <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(l.amount)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t border-gray-300 bg-gray-50">
              <tr><td colSpan={2} className="px-4 py-2 text-sm font-semibold text-gray-900">Total Expenses</td><td className="px-4 py-2 text-right font-mono text-sm font-semibold tabular-nums text-gray-900">{fmt(totalExpenses)}</td></tr>
            </tfoot>
          </table>

          <div className={`px-4 py-4 flex items-center justify-between border-t-2 border-gray-900 ${netIncome >= 0 ? 'bg-green-50' : 'bg-red-50'}`}>
            <span className="text-base font-bold text-gray-900">Net Income</span>
            <span className={`font-mono font-bold text-lg tabular-nums ${netIncome >= 0 ? 'text-green-700' : 'text-red-700'}`}>{fmt(netIncome)}</span>
          </div>
        </div>
      )}
    </div>
  )
}
