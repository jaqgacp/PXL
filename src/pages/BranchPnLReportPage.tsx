import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { branch_id: string | null; branch_name: string; revenue: number; expenses: number }
type GLRow = { branch_id: string | null; account_type: string; debit_amount: number; credit_amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function BranchPnLReportPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: branches }, { data: glData }] = await Promise.all([
      supabase.from('branches').select('id,branch_name').eq('company_id', companyId),
      supabase.from('vw_general_ledger').select('branch_id,account_type,debit_amount,credit_amount')
        .eq('company_id', companyId).gte('je_date', dateFrom).lte('je_date', dateTo).in('account_type', ['revenue', 'expense']),
    ])

    const branchNames: Record<string, string> = {}
    for (const b of (branches as { id: string; branch_name: string }[]) || []) branchNames[b.id] = b.branch_name

    const byBranch: Record<string, Row> = {}
    for (const r of (glData as GLRow[]) || []) {
      const key = r.branch_id || 'unassigned'
      if (!byBranch[key]) byBranch[key] = { branch_id: r.branch_id, branch_name: r.branch_id ? branchNames[r.branch_id] || 'Unknown Branch' : 'Unassigned', revenue: 0, expenses: 0 }
      if (r.account_type === 'revenue') byBranch[key].revenue += Number(r.credit_amount) - Number(r.debit_amount)
      if (r.account_type === 'expense') byBranch[key].expenses += Number(r.debit_amount) - Number(r.credit_amount)
    }

    setRows(Object.values(byBranch).sort((a, b) => b.revenue - a.revenue))
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalRevenue = rows.reduce((s, r) => s + r.revenue, 0)
  const totalExpenses = rows.reduce((s, r) => s + r.expenses, 0)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Branch P&amp;L</h1><p className="text-sm text-gray-500 mt-0.5">Revenue and expenses by branch</p></div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Revenue</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Expenses</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Net Income</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Margin %</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No branch activity in this period.'}</td></tr>
              ) : rows.map(r => {
                const net = r.revenue - r.expenses
                const margin = r.revenue !== 0 ? (net / r.revenue) * 100 : 0
                return (
                  <tr key={r.branch_id || 'unassigned'} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="px-4 py-2 text-gray-700">{r.branch_name}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.revenue)}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.expenses)}</td>
                    <td className={`px-4 py-2 text-right font-mono tabular-nums font-semibold ${net >= 0 ? 'text-green-600' : 'text-red-600'}`}>{fmt(net)}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-xs text-gray-500">{margin.toFixed(1)}%</td>
                  </tr>
                )
              })}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalRevenue)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalExpenses)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalRevenue - totalExpenses)}</td><td /></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
