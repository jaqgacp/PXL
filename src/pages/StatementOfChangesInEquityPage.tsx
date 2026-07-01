import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COA = { id: string; account_code: string; account_name: string; account_type: string }
type GLAgg = { account_id: string; debit_amount: number; credit_amount: number }
type FiscalYear = { id: string; year_name: string; start_date: string; end_date: string }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function StatementOfChangesInEquityPage() {
  const { companyId } = useAppCtx()
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [fyId, setFyId] = useState('')
  const [beginningEquity, setBeginningEquity] = useState(0)
  const [equityMovement, setEquityMovement] = useState(0)
  const [netIncome, setNetIncome] = useState(0)
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)

  const loadYears = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('fiscal_years').select('id,year_name,start_date,end_date').eq('company_id', companyId).order('start_date', { ascending: false })
    const years = (data as FiscalYear[]) || []
    setFiscalYears(years)
    if (years.length && !fyId) setFyId(years[0].id)
  }, [companyId, fyId])

  useEffect(() => { if (companyId) loadYears() }, [loadYears, companyId])

  const run = useCallback(async () => {
    if (!companyId || !fyId) return
    const fy = fiscalYears.find(f => f.id === fyId)
    if (!fy) return
    setLoading(true)

    const [{ data: coaData }, { data: openGl }, { data: periodGl }] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type').eq('company_id', companyId).eq('is_active', true).eq('is_postable', true),
      supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount').eq('company_id', companyId).lt('je_date', fy.start_date),
      supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount').eq('company_id', companyId).gte('je_date', fy.start_date).lte('je_date', fy.end_date),
    ])

    const coaById: Record<string, COA> = {}
    for (const a of (coaData as COA[]) || []) coaById[a.id] = a

    let openEquity = 0, movEquity = 0, rev = 0, exp = 0
    for (const r of (openGl as GLAgg[]) || []) {
      const acc = coaById[r.account_id]
      if (acc?.account_type === 'equity') openEquity += Number(r.credit_amount) - Number(r.debit_amount)
    }
    for (const r of (periodGl as GLAgg[]) || []) {
      const acc = coaById[r.account_id]
      if (!acc) continue
      if (acc.account_type === 'equity') movEquity += Number(r.credit_amount) - Number(r.debit_amount)
      if (acc.account_type === 'revenue') rev += Number(r.credit_amount) - Number(r.debit_amount)
      if (acc.account_type === 'expense') exp += Number(r.debit_amount) - Number(r.credit_amount)
    }

    setBeginningEquity(openEquity)
    setEquityMovement(movEquity)
    setNetIncome(rev - exp)
    setApplied(true)
    setLoading(false)
  }, [companyId, fyId, fiscalYears])

  useEffect(() => { if (companyId && fyId) run() }, [run, companyId, fyId])

  const endingEquity = beginningEquity + equityMovement + netIncome
  const selectedFy = fiscalYears.find(f => f.id === fyId)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Statement of Changes in Equity</h1>
          <p className="text-sm text-gray-500 mt-0.5">Roll-forward of equity balances for the fiscal year</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={fyId} onChange={e => setFyId(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {fiscalYears.map(fy => <option key={fy.id} value={fy.id}>{fy.year_name}</option>)}
        </select>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : applied && (
        <div className="max-w-2xl bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">{selectedFy?.year_name}</h2></div>
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-100">
                <td className="px-4 py-2.5 text-gray-700">Beginning Equity Balance</td>
                <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(beginningEquity)}</td>
              </tr>
              <tr className="border-b border-gray-100">
                <td className="px-4 py-2.5 text-gray-700">Add: Net Income for the Year</td>
                <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(netIncome)}</td>
              </tr>
              <tr className="border-b border-gray-100">
                <td className="px-4 py-2.5 text-gray-700">Other Equity Movements (contributions, withdrawals, adjustments)</td>
                <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(equityMovement)}</td>
              </tr>
            </tbody>
            <tfoot className="border-t-2 border-gray-900 bg-gray-50">
              <tr><td className="px-4 py-3 text-base font-bold text-gray-900">Ending Equity Balance</td><td className="px-4 py-3 text-right font-mono text-lg font-bold tabular-nums text-gray-900">{fmt(endingEquity)}</td></tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
