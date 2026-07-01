import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Asset = { id: string; asset_number: string; asset_name: string; acquisition_cost: number; salvage_value: number; useful_life_months: number; depreciation_method: string }
type Entry = { asset_id: string; depreciation_amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function BookVsTaxDepreciationReportPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<{ asset: Asset; book: number; tax: number }[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: assets }, { data: entries }] = await Promise.all([
      supabase.from('fixed_assets').select('id,asset_number,asset_name,acquisition_cost,salvage_value,useful_life_months,depreciation_method').eq('company_id', companyId),
      supabase.from('asset_depreciation_entries').select('asset_id,depreciation_amount').eq('company_id', companyId).eq('status', 'posted').gte('entry_date', dateFrom).lte('entry_date', dateTo),
    ])

    const bookByAsset: Record<string, number> = {}
    for (const e of (entries as Entry[]) || []) bookByAsset[e.asset_id] = (bookByAsset[e.asset_id] || 0) + Number(e.depreciation_amount)

    const monthsInRange = Math.max(1, Math.round((new Date(dateTo).getTime() - new Date(dateFrom).getTime()) / (1000 * 60 * 60 * 24 * 30)))

    const result = ((assets as Asset[]) || []).map(a => {
      const straightLineMonthly = (Number(a.acquisition_cost) - Number(a.salvage_value)) / a.useful_life_months
      const taxDep = straightLineMonthly * Math.min(monthsInRange, a.useful_life_months)
      return { asset: a, book: bookByAsset[a.id] || 0, tax: taxDep }
    }).filter(r => r.book > 0.005 || r.tax > 0.005)

    setRows(result)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalBook = rows.reduce((s, r) => s + r.book, 0)
  const totalTax = rows.reduce((s, r) => s + r.tax, 0)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Book vs Tax Depreciation Report</h1><p className="text-sm text-gray-500 mt-0.5">Book depreciation (actual method) vs. straight-line tax depreciation</p></div>
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
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Book Method</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Book Depreciation</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Depreciation (SL)</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Variance</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No depreciation activity in this period.'}</td></tr>
              ) : rows.map(r => {
                const variance = r.book - r.tax
                return (
                  <tr key={r.asset.id} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="px-4 py-2 text-gray-700">{r.asset.asset_number} — {r.asset.asset_name}</td>
                    <td className="px-4 py-2 text-gray-500 capitalize">{r.asset.depreciation_method.replace('_', ' ')}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.book)}</td>
                    <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax)}</td>
                    <td className={`px-4 py-2 text-right font-mono tabular-nums font-semibold ${Math.abs(variance) < 0.01 ? 'text-gray-400' : variance > 0 ? 'text-amber-600' : 'text-blue-600'}`}>{fmt(variance)}</td>
                  </tr>
                )
              })}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBook)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalTax)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBook - totalTax)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
