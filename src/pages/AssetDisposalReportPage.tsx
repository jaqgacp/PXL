import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  disposal_date: string
  disposal_type: string
  cost_at_disposal: number
  accum_depr_at_disposal: number
  net_book_value: number
  proceeds_amount: number
  gain_loss_amount: number
  fixed_assets: { asset_number: string; asset_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'
const DISPOSAL_LABELS: Record<string, string> = { sale: 'Sale', write_off: 'Write-Off', donation: 'Donation', trade_in: 'Trade-In' }

export default function AssetDisposalReportPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('asset_disposals')
      .select('id,disposal_date,disposal_type,cost_at_disposal,accum_depr_at_disposal,net_book_value,proceeds_amount,gain_loss_amount,fixed_assets(asset_number,asset_name)')
      .eq('company_id', companyId).gte('disposal_date', dateFrom).lte('disposal_date', dateTo).order('disposal_date', { ascending: false })
    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalProceeds = rows.reduce((s, r) => s + r.proceeds_amount, 0)
  const totalGainLoss = rows.reduce((s, r) => s + r.gain_loss_amount, 0)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Asset Disposal Report</h1><p className="text-sm text-gray-500 mt-0.5">Disposed fixed assets — proceeds and gain/loss on disposal</p></div>
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
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">NBV</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Proceeds</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gain/(Loss)</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No asset disposals in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.disposal_date}</td>
                  <td className="px-4 py-2 text-gray-700">{r.fixed_assets?.asset_number} — {r.fixed_assets?.asset_name}</td>
                  <td className="px-4 py-2 text-gray-500">{DISPOSAL_LABELS[r.disposal_type] || r.disposal_type}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.net_book_value)}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.proceeds_amount)}</td>
                  <td className={`px-4 py-2 text-right font-mono tabular-nums font-semibold ${r.gain_loss_amount >= 0 ? 'text-green-600' : 'text-red-600'}`}>{fmt(r.gain_loss_amount)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} disposal{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalProceeds)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalGainLoss)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
