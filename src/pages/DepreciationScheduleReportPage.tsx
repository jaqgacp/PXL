import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Asset = { id: string; asset_number: string; asset_name: string; acquisition_cost: number; salvage_value: number; useful_life_months: number; depreciation_method: string; status: string }
type Entry = { period_number: number; entry_date: string; depreciation_amount: number; accumulated_depr_after: number; net_book_value_after: number; status: string }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function DepreciationScheduleReportPage() {
  const { companyId } = useAppCtx()
  const [assets, setAssets] = useState<Asset[]>([])
  const [selectedAssetId, setSelectedAssetId] = useState('')
  const [entries, setEntries] = useState<Entry[]>([])
  const [loading, setLoading] = useState(false)

  const loadAssets = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('fixed_assets').select('id,asset_number,asset_name,acquisition_cost,salvage_value,useful_life_months,depreciation_method,status')
      .eq('company_id', companyId).order('asset_number')
    const list = (data as Asset[]) || []
    setAssets(list)
    if (list.length && !selectedAssetId) setSelectedAssetId(list[0].id)
  }, [companyId, selectedAssetId])

  useEffect(() => { if (companyId) loadAssets() }, [loadAssets, companyId])

  const loadEntries = useCallback(async () => {
    if (!selectedAssetId) return
    setLoading(true)
    const { data } = await supabase.from('asset_depreciation_entries')
      .select('period_number,entry_date,depreciation_amount,accumulated_depr_after,net_book_value_after,status')
      .eq('asset_id', selectedAssetId).order('period_number')
    setEntries((data as Entry[]) || [])
    setLoading(false)
  }, [selectedAssetId])

  useEffect(() => { if (selectedAssetId) loadEntries() }, [loadEntries, selectedAssetId])

  const asset = assets.find(a => a.id === selectedAssetId)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Depreciation Schedule Report</h1><p className="text-sm text-gray-500 mt-0.5">Full month-by-month depreciation schedule per asset</p></div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={selectedAssetId} onChange={e => setSelectedAssetId(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-96">
          {assets.map(a => <option key={a.id} value={a.id}>{a.asset_number} — {a.asset_name}</option>)}
        </select>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : asset && (
        <div className="grid grid-cols-5 gap-4">
          <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Cost</p><p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(asset.acquisition_cost)}</p></div>
          <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Salvage Value</p><p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(asset.salvage_value)}</p></div>
          <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Useful Life</p><p className="text-lg font-bold text-gray-900 mt-1">{asset.useful_life_months} mo.</p></div>
          <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Method</p><p className="text-lg font-bold text-gray-900 mt-1 capitalize">{asset.depreciation_method.replace('_', ' ')}</p></div>
          <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Status</p><p className="text-lg font-bold text-gray-900 mt-1 capitalize">{asset.status.replace('_', ' ')}</p></div>
        </div>
      )}

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Depreciation</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Accumulated</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Net Book Value</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            </tr></thead>
            <tbody>
              {entries.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">No schedule entries for this asset.</td></tr>
              ) : entries.map(e => (
                <tr key={e.period_number} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{e.period_number}</td>
                  <td className="px-4 py-2 text-gray-500">{e.entry_date}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(e.depreciation_amount)}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(e.accumulated_depr_after)}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(e.net_book_value_after)}</td>
                  <td className="px-4 py-2 text-xs text-gray-500 capitalize">{e.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
