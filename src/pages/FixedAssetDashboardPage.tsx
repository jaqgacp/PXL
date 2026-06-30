import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Stats = {
  total_assets: number
  active: number
  fully_depreciated: number
  disposed: number
  impaired: number
  total_cost: number
  total_accum_depr: number
  total_nbv: number
}

type AssetSummary = {
  id: string
  asset_number: string
  asset_name: string
  category_name: string
  acquisition_date: string
  acquisition_cost: number
  accum_depr: number
  nbv: number
  status: string
  pending_depr_periods: number
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'
const STATUS_COLOR: Record<string, string> = {
  active: 'bg-green-50 text-green-700',
  fully_depreciated: 'bg-blue-50 text-blue-700',
  disposed: 'bg-gray-100 text-gray-500',
  impaired: 'bg-amber-50 text-amber-700',
  draft: 'bg-yellow-50 text-yellow-700',
}

export default function FixedAssetDashboardPage() {
  const { companyId } = useAppCtx()
  const [stats, setStats] = useState<Stats | null>(null)
  const [assets, setAssets] = useState<AssetSummary[]>([])
  const [filter, setFilter] = useState<string>('all')
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: faData }, { data: deprData }] = await Promise.all([
      supabase.from('fixed_assets').select(`
        id, asset_number, asset_name, acquisition_date, acquisition_cost, salvage_value,
        useful_life_months, depreciation_method, status,
        fixed_asset_categories!inner(category_name)
      `).eq('company_id', companyId),
      supabase.from('asset_depreciation_entries')
        .select('asset_id, depreciation_amount, status')
        .eq('company_id', companyId),
    ])

    if (!faData) { setLoading(false); return }

    const deprMap: Record<string, { posted: number; pending: number }> = {}
    for (const d of (deprData || [])) {
      if (!deprMap[d.asset_id]) deprMap[d.asset_id] = { posted: 0, pending: 0 }
      if (d.status === 'posted') deprMap[d.asset_id].posted += Number(d.depreciation_amount)
      if (d.status === 'pending') deprMap[d.asset_id].pending++
    }

    const summaries: AssetSummary[] = faData.map((a: any) => {
      const posted = deprMap[a.id]?.posted ?? 0
      return {
        id: a.id,
        asset_number: a.asset_number,
        asset_name: a.asset_name,
        category_name: a.fixed_asset_categories?.category_name ?? '',
        acquisition_date: a.acquisition_date,
        acquisition_cost: Number(a.acquisition_cost),
        accum_depr: posted,
        nbv: Number(a.acquisition_cost) - posted,
        status: a.status,
        pending_depr_periods: deprMap[a.id]?.pending ?? 0,
      }
    })

    const totals = summaries.reduce((acc, a) => ({
      total_assets: acc.total_assets + 1,
      active: acc.active + (a.status === 'active' ? 1 : 0),
      fully_depreciated: acc.fully_depreciated + (a.status === 'fully_depreciated' ? 1 : 0),
      disposed: acc.disposed + (a.status === 'disposed' ? 1 : 0),
      impaired: acc.impaired + (a.status === 'impaired' ? 1 : 0),
      total_cost: acc.total_cost + a.acquisition_cost,
      total_accum_depr: acc.total_accum_depr + a.accum_depr,
      total_nbv: acc.total_nbv + a.nbv,
    }), { total_assets: 0, active: 0, fully_depreciated: 0, disposed: 0, impaired: 0, total_cost: 0, total_accum_depr: 0, total_nbv: 0 })

    setStats(totals)
    setAssets(summaries)
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  const visible = assets.filter(a => {
    if (filter !== 'all' && a.status !== filter) return false
    if (search && !a.asset_name.toLowerCase().includes(search.toLowerCase()) && !a.asset_number.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Fixed Assets Dashboard</span>
      </div>

      <div className="px-5 py-4 space-y-4">
        {/* KPI Cards */}
        {stats && (
          <div className="grid grid-cols-4 gap-3">
            {[
              { label: 'Total Assets', value: stats.total_assets.toString(), sub: `${stats.active} active` },
              { label: 'Gross Cost', value: `₱ ${fmt(stats.total_cost)}`, sub: 'Acquisition cost' },
              { label: 'Accum. Depreciation', value: `₱ ${fmt(stats.total_accum_depr)}`, sub: `${((stats.total_accum_depr / (stats.total_cost || 1)) * 100).toFixed(1)}% of cost` },
              { label: 'Net Book Value', value: `₱ ${fmt(stats.total_nbv)}`, sub: 'Carrying amount' },
            ].map(k => (
              <div key={k.label} className="bg-white border border-gray-200 rounded-lg px-4 py-3">
                <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{k.label}</p>
                <p className="text-lg font-semibold text-gray-900 mt-1 font-mono tabular-nums">{k.value}</p>
                <p className="text-[10px] text-gray-500 mt-0.5">{k.sub}</p>
              </div>
            ))}
          </div>
        )}

        {/* Status breakdown */}
        {stats && (
          <div className="grid grid-cols-4 gap-3">
            {[
              { label: 'Active', count: stats.active, key: 'active', color: 'text-green-700 bg-green-50' },
              { label: 'Fully Depreciated', count: stats.fully_depreciated, key: 'fully_depreciated', color: 'text-blue-700 bg-blue-50' },
              { label: 'Impaired', count: stats.impaired, key: 'impaired', color: 'text-amber-700 bg-amber-50' },
              { label: 'Disposed', count: stats.disposed, key: 'disposed', color: 'text-gray-600 bg-gray-100' },
            ].map(s => (
              <button key={s.key}
                onClick={() => setFilter(filter === s.key ? 'all' : s.key)}
                className={`bg-white border rounded-lg px-4 py-2.5 text-left transition-all ${filter === s.key ? 'border-gray-900 shadow-sm' : 'border-gray-200 hover:border-gray-300'}`}>
                <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{s.label}</p>
                <p className={`text-xl font-bold mt-0.5 ${s.color.split(' ')[0]}`}>{s.count}</p>
              </button>
            ))}
          </div>
        )}

        {/* Asset list */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2">
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search assets…"
              className="border border-gray-200 rounded px-2.5 py-1 text-xs w-56 focus:outline-none focus:ring-1 focus:ring-gray-900" />
            <span className="text-xs text-gray-400 ml-auto">{visible.length} assets</span>
          </div>
          {loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading…</div>
          ) : visible.length === 0 ? (
            <div className="py-12 text-center text-xs text-gray-400">No assets found</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Asset #','Name','Category','Acquired','Cost (₱)','Accum. Depr (₱)','NBV (₱)','Status','Pending Depr'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visible.map(a => (
                    <tr key={a.id} className="hover:bg-gray-50/60">
                      <td className="px-3 py-2 font-mono font-semibold text-gray-900">{a.asset_number}</td>
                      <td className="px-3 py-2 text-gray-800 max-w-[180px] truncate">{a.asset_name}</td>
                      <td className="px-3 py-2 text-gray-500">{a.category_name}</td>
                      <td className="px-3 py-2 text-gray-500 font-mono">{a.acquisition_date}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-800">{fmt(a.acquisition_cost)}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-500">{fmt(a.accum_depr)}</td>
                      <td className="px-3 py-2 text-right font-mono font-semibold text-gray-900">{fmt(a.nbv)}</td>
                      <td className="px-3 py-2">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${STATUS_COLOR[a.status] || 'bg-gray-100 text-gray-600'}`}>
                          {a.status.replace(/_/g, ' ')}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-center">
                        {a.pending_depr_periods > 0
                          ? <span className="text-xs font-mono text-amber-700 bg-amber-50 px-2 py-0.5 rounded">{a.pending_depr_periods} mo</span>
                          : <span className="text-gray-300">—</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
