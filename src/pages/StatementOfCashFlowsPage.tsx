import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function StatementOfCashFlowsPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [loading, setLoading] = useState(false)
  const [applied, setApplied] = useState(false)

  const [netIncome, setNetIncome] = useState(0)
  const [depreciation, setDepreciation] = useState(0)
  const [arChange, setArChange] = useState(0)
  const [apChange, setApChange] = useState(0)
  const [assetAcquisitions, setAssetAcquisitions] = useState(0)
  const [disposalProceeds, setDisposalProceeds] = useState(0)
  const [financingMovement, setFinancingMovement] = useState(0)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const { data: cfg } = await supabase.from('company_accounting_config').select('ar_account_id,ap_account_id').eq('company_id', companyId).maybeSingle()
    const arAccountId = cfg?.ar_account_id as string | undefined
    const apAccountId = cfg?.ap_account_id as string | undefined

    const [{ data: periodGl }, { data: depData }, { data: acqData }, { data: dispData }] = await Promise.all([
      supabase.from('vw_general_ledger').select('account_id,account_type,debit_amount,credit_amount').eq('company_id', companyId).gte('je_date', dateFrom).lte('je_date', dateTo),
      supabase.from('asset_depreciation_entries').select('depreciation_amount').eq('company_id', companyId).eq('status', 'posted').gte('entry_date', dateFrom).lte('entry_date', dateTo),
      supabase.from('fixed_assets').select('acquisition_cost').eq('company_id', companyId).gte('acquisition_date', dateFrom).lte('acquisition_date', dateTo),
      supabase.from('asset_disposals').select('proceeds_amount').eq('company_id', companyId).gte('disposal_date', dateFrom).lte('disposal_date', dateTo),
    ])

    let rev = 0, exp = 0, arDelta = 0, apDelta = 0, equityMov = 0
    for (const r of (periodGl as { account_id: string; account_type: string; debit_amount: number; credit_amount: number }[]) || []) {
      if (r.account_type === 'revenue') rev += Number(r.credit_amount) - Number(r.debit_amount)
      if (r.account_type === 'expense') exp += Number(r.debit_amount) - Number(r.credit_amount)
      if (r.account_type === 'equity') equityMov += Number(r.credit_amount) - Number(r.debit_amount)
      if (arAccountId && r.account_id === arAccountId) arDelta += Number(r.debit_amount) - Number(r.credit_amount)
      if (apAccountId && r.account_id === apAccountId) apDelta += Number(r.credit_amount) - Number(r.debit_amount)
    }

    setNetIncome(rev - exp)
    setDepreciation(((depData || []) as { depreciation_amount: number }[]).reduce((s, r) => s + Number(r.depreciation_amount), 0))
    setArChange(-arDelta)
    setApChange(apDelta)
    setAssetAcquisitions(-((acqData || []) as { acquisition_cost: number }[]).reduce((s, r) => s + Number(r.acquisition_cost), 0))
    setDisposalProceeds(((dispData || []) as { proceeds_amount: number }[]).reduce((s, r) => s + Number(r.proceeds_amount), 0))
    setFinancingMovement(equityMov - (rev - exp))
    setApplied(true)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const operatingTotal = netIncome + depreciation + arChange + apChange
  const investingTotal = assetAcquisitions + disposalProceeds
  const financingTotal = financingMovement
  const netCashChange = operatingTotal + investingTotal + financingTotal

  const Row = ({ label, value, italic }: { label: string; value: number; italic?: boolean }) => (
    <tr className="border-b border-gray-100">
      <td className={`px-4 py-1.5 text-gray-700 ${italic ? 'italic' : ''}`}>{label}</td>
      <td className="px-4 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(value)}</td>
    </tr>
  )

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Statement of Cash Flows</h1>
          <p className="text-sm text-gray-500 mt-0.5">Indirect method</p>
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
        <div className="max-w-2xl bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Operating Activities</h2></div>
          <table className="w-full text-sm">
            <tbody>
              <Row label="Net Income" value={netIncome} />
              <Row label="Add: Depreciation" value={depreciation} italic />
              <Row label="(Increase)/Decrease in Accounts Receivable" value={arChange} italic />
              <Row label="Increase/(Decrease) in Accounts Payable" value={apChange} italic />
            </tbody>
            <tfoot className="border-t border-gray-300 bg-gray-50">
              <tr><td className="px-4 py-2 text-sm font-semibold text-gray-900">Net Cash from Operating Activities</td><td className="px-4 py-2 text-right font-mono text-sm font-semibold tabular-nums text-gray-900">{fmt(operatingTotal)}</td></tr>
            </tfoot>
          </table>

          <div className="px-4 py-3 border-b border-t-4 border-t-gray-100 border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Investing Activities</h2></div>
          <table className="w-full text-sm">
            <tbody>
              <Row label="Fixed Asset Acquisitions" value={assetAcquisitions} />
              <Row label="Proceeds from Asset Disposals" value={disposalProceeds} />
            </tbody>
            <tfoot className="border-t border-gray-300 bg-gray-50">
              <tr><td className="px-4 py-2 text-sm font-semibold text-gray-900">Net Cash from Investing Activities</td><td className="px-4 py-2 text-right font-mono text-sm font-semibold tabular-nums text-gray-900">{fmt(investingTotal)}</td></tr>
            </tfoot>
          </table>

          <div className="px-4 py-3 border-b border-t-4 border-t-gray-100 border-gray-100 bg-gray-50"><h2 className="text-sm font-semibold text-gray-900">Financing Activities</h2></div>
          <table className="w-full text-sm">
            <tbody>
              <Row label="Equity Contributions / (Withdrawals)" value={financingMovement} />
            </tbody>
            <tfoot className="border-t border-gray-300 bg-gray-50">
              <tr><td className="px-4 py-2 text-sm font-semibold text-gray-900">Net Cash from Financing Activities</td><td className="px-4 py-2 text-right font-mono text-sm font-semibold tabular-nums text-gray-900">{fmt(financingTotal)}</td></tr>
            </tfoot>
          </table>

          <div className={`px-4 py-4 flex items-center justify-between border-t-2 border-gray-900 ${netCashChange >= 0 ? 'bg-green-50' : 'bg-red-50'}`}>
            <span className="text-base font-bold text-gray-900">Net Increase (Decrease) in Cash</span>
            <span className={`font-mono font-bold text-lg tabular-nums ${netCashChange >= 0 ? 'text-green-700' : 'text-red-700'}`}>{fmt(netCashChange)}</span>
          </div>
        </div>
      )}
    </div>
  )
}
