import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COA = { id: string; account_code: string; account_name: string; account_type: string; parent_id: string | null }
type GLAgg = { account_id: string; debit_amount: number; credit_amount: number }
type Line = { account_id: string; account_code: string; account_name: string; amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

export default function BalanceSheetPage() {
  const { companyId } = useAppCtx()
  const [asOfDate, setAsOfDate] = useState(today())
  const [assets, setAssets] = useState<Line[]>([])
  const [liabilities, setLiabilities] = useState<Line[]>([])
  const [equity, setEquity] = useState<Line[]>([])
  const [netIncome, setNetIncome] = useState(0)
  const [periodStart, setPeriodStart] = useState(`${new Date().getFullYear()}-01-01`)
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: accounts }, { data: glData }, { data: fiscalYears }] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type,parent_id')
        .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
      supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount,account_type')
        .eq('company_id', companyId).lte('je_date', asOfDate),
      supabase.from('fiscal_years').select('start_date,end_date').eq('company_id', companyId)
        .lte('start_date', asOfDate).gte('end_date', asOfDate).limit(1),
    ])

    const coaList = (accounts as COA[]) || []
    const coaById: Record<string, COA> = {}
    for (const a of coaList) coaById[a.id] = a

    const balances: Record<string, number> = {}
    for (const r of (glData as (GLAgg & { account_type: string })[]) || []) {
      balances[r.account_id] = (balances[r.account_id] || 0) + Number(r.debit_amount) - Number(r.credit_amount)
    }

    const assetLines: Line[] = [], liabLines: Line[] = [], eqLines: Line[] = []
    let revTotal = 0, expTotal = 0

    for (const a of coaList) {
      const net = balances[a.id] || 0
      if (Math.abs(net) < 0.005 && a.account_type !== 'asset' && a.account_type !== 'liability' && a.account_type !== 'equity') continue
      if (a.account_type === 'asset') { if (Math.abs(net) >= 0.005) assetLines.push({ account_id: a.id, account_code: a.account_code, account_name: a.account_name, amount: net }) }
      else if (a.account_type === 'liability') { if (Math.abs(net) >= 0.005) liabLines.push({ account_id: a.id, account_code: a.account_code, account_name: a.account_name, amount: -net }) }
      else if (a.account_type === 'equity') { if (Math.abs(net) >= 0.005) eqLines.push({ account_id: a.id, account_code: a.account_code, account_name: a.account_name, amount: -net }) }
      else if (a.account_type === 'revenue') revTotal += -net
      else if (a.account_type === 'expense') expTotal += net
    }

    const fy = (fiscalYears || [])[0] as { start_date: string; end_date: string } | undefined
    setPeriodStart(fy?.start_date || `${asOfDate.slice(0, 4)}-01-01`)
    let ytdNetIncome = revTotal - expTotal
    if (fy) {
      // Recompute net income strictly within the current fiscal year (revenue/expense accounts reset each FY)
      const { data: fyGl } = await supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount,account_type')
        .eq('company_id', companyId).gte('je_date', fy.start_date).lte('je_date', asOfDate)
      let rev = 0, exp = 0
      for (const r of (fyGl as (GLAgg & { account_type: string })[]) || []) {
        if (r.account_type === 'revenue') rev += Number(r.credit_amount) - Number(r.debit_amount)
        if (r.account_type === 'expense') exp += Number(r.debit_amount) - Number(r.credit_amount)
      }
      ytdNetIncome = rev - exp
    }

    setAssets(assetLines.sort((a, b) => a.account_code.localeCompare(b.account_code)))
    setLiabilities(liabLines.sort((a, b) => a.account_code.localeCompare(b.account_code)))
    setEquity(eqLines.sort((a, b) => a.account_code.localeCompare(b.account_code)))
    setNetIncome(ytdNetIncome)
    setApplied(true)
    setLoading(false)
  }, [companyId, asOfDate])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalAssets = assets.reduce((s, l) => s + l.amount, 0)
  const totalLiabilities = liabilities.reduce((s, l) => s + l.amount, 0)
  const totalEquity = equity.reduce((s, l) => s + l.amount, 0) + netIncome
  const totalLiabEquity = totalLiabilities + totalEquity
  const balanced = Math.abs(totalAssets - totalLiabEquity) <= 0.5

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Balance Sheet</h1>
          <p className="text-sm text-gray-500 mt-0.5">Statement of Financial Position</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <label className="text-xs text-gray-500">As of</label>
        <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : applied && (
        <div className="grid grid-cols-2 gap-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Assets</h2></div>
            <table className="w-full text-sm">
              <tbody>
                {assets.length === 0 ? <tr><td className="px-4 py-8 text-center text-gray-400">No asset balances.</td></tr> : assets.map(l => (
                  <tr key={l.account_code} className="border-b border-gray-100">
                    <td className="px-4 py-1.5 text-gray-500 text-xs w-20">{l.account_code}</td>
                    <td className="px-4 py-1.5">
                      <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${periodStart}&dateTo=${asOfDate}`} className="text-blue-700 hover:text-blue-900">
                        {l.account_name}
                      </Link>
                    </td>
                    <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(l.amount)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={2} className="px-4 py-2 text-sm font-bold text-gray-900">Total Assets</td><td className="px-4 py-2 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalAssets)}</td></tr>
              </tfoot>
            </table>
          </div>

          <div className="space-y-4">
            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Liabilities</h2></div>
              <table className="w-full text-sm">
                <tbody>
                  {liabilities.length === 0 ? <tr><td className="px-4 py-8 text-center text-gray-400">No liability balances.</td></tr> : liabilities.map(l => (
                    <tr key={l.account_code} className="border-b border-gray-100">
                      <td className="px-4 py-1.5 text-gray-500 text-xs w-20">{l.account_code}</td>
                      <td className="px-4 py-1.5">
                        <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${periodStart}&dateTo=${asOfDate}`} className="text-blue-700 hover:text-blue-900">
                          {l.account_name}
                        </Link>
                      </td>
                      <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(l.amount)}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr><td colSpan={2} className="px-4 py-2 text-sm font-bold text-gray-900">Total Liabilities</td><td className="px-4 py-2 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalLiabilities)}</td></tr>
                </tfoot>
              </table>
            </div>

            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Equity</h2></div>
              <table className="w-full text-sm">
                <tbody>
                  {equity.map(l => (
                    <tr key={l.account_code} className="border-b border-gray-100">
                      <td className="px-4 py-1.5 text-gray-500 text-xs w-20">{l.account_code}</td>
                      <td className="px-4 py-1.5">
                        <Link to={`/account-detail-ledger?accountId=${l.account_id}&dateFrom=${periodStart}&dateTo=${asOfDate}`} className="text-blue-700 hover:text-blue-900">
                          {l.account_name}
                        </Link>
                      </td>
                      <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(l.amount)}</td>
                    </tr>
                  ))}
                  <tr className="border-b border-gray-100">
                    <td className="px-4 py-1.5" />
                    <td className="px-4 py-1.5 text-gray-700 italic">Net Income (Current Fiscal Year)</td>
                    <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(netIncome)}</td>
                  </tr>
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr><td colSpan={2} className="px-4 py-2 text-sm font-bold text-gray-900">Total Equity</td><td className="px-4 py-2 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalEquity)}</td></tr>
                </tfoot>
              </table>
            </div>

            <div className={`rounded-lg p-4 flex items-center justify-between ${balanced ? 'bg-green-50 border border-green-200' : 'bg-red-50 border border-red-200'}`}>
              <span className={`text-sm font-semibold ${balanced ? 'text-green-700' : 'text-red-700'}`}>Total Liabilities + Equity</span>
              <span className={`font-mono font-bold tabular-nums ${balanced ? 'text-green-700' : 'text-red-700'}`}>{fmt(totalLiabEquity)}</span>
            </div>
            {!balanced && <p className="text-xs text-red-600 text-center">⚠ Balance sheet does not balance — check unposted or misclassified entries.</p>}
          </div>
        </div>
      )}
    </div>
  )
}
