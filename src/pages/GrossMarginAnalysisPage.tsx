import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function GrossMarginAnalysisPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [revenue, setRevenue] = useState(0)
  const [cogs, setCogs] = useState(0)
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const { data: items } = await supabase.from('items').select('cogs_account_id').eq('company_id', companyId).not('cogs_account_id', 'is', null)
    const cogsAccountIds = Array.from(new Set(((items || []) as { cogs_account_id: string }[]).map(i => i.cogs_account_id)))

    const { data: glData } = await supabase.from('vw_general_ledger').select('account_id,account_type,debit_amount,credit_amount')
      .eq('company_id', companyId).gte('je_date', dateFrom).lte('je_date', dateTo)

    let rev = 0, cogsTotal = 0
    for (const r of (glData as { account_id: string; account_type: string; debit_amount: number; credit_amount: number }[]) || []) {
      if (r.account_type === 'revenue') rev += Number(r.credit_amount) - Number(r.debit_amount)
      if (cogsAccountIds.includes(r.account_id)) cogsTotal += Number(r.debit_amount) - Number(r.credit_amount)
    }

    setRevenue(rev)
    setCogs(cogsTotal)
    setApplied(true)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const grossProfit = revenue - cogs
  const marginPct = revenue !== 0 ? (grossProfit / revenue) * 100 : 0

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Gross Margin Analysis</h1><p className="text-sm text-gray-500 mt-0.5">Revenue less Cost of Goods Sold</p></div>
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
        <div className="max-w-lg bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-100"><td className="px-4 py-2.5 text-gray-700">Net Revenue</td><td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(revenue)}</td></tr>
              <tr className="border-b border-gray-100"><td className="px-4 py-2.5 text-gray-700">Less: Cost of Goods Sold</td><td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(cogs)}</td></tr>
            </tbody>
            <tfoot className="border-t-2 border-gray-900 bg-gray-50">
              <tr><td className="px-4 py-3 text-base font-bold text-gray-900">Gross Profit</td><td className="px-4 py-3 text-right font-mono text-lg font-bold tabular-nums text-gray-900">{fmt(grossProfit)}</td></tr>
              <tr><td className="px-4 py-2 text-sm text-gray-600">Gross Margin %</td><td className={`px-4 py-2 text-right font-mono text-sm font-semibold tabular-nums ${marginPct >= 0 ? 'text-green-600' : 'text-red-600'}`}>{marginPct.toFixed(1)}%</td></tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
