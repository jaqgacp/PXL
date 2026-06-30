import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Asset = {
  id: string
  asset_number: string
  asset_name: string
  description: string | null
  category_id: string
  category_name: string
  branch_name: string | null
  department_name: string | null
  acquisition_date: string
  depreciation_start_date: string
  acquisition_cost: number
  salvage_value: number
  useful_life_months: number
  depreciation_method: string
  serial_number: string | null
  location: string | null
  status: string
  accum_depr: number
  nbv: number
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'
const METHODS: Record<string, string> = {
  straight_line: 'SLM', declining_balance: 'DDB', sum_of_years: 'SYD', none: 'None'
}
const STATUS_COLOR: Record<string, string> = {
  active: 'bg-green-50 text-green-700',
  fully_depreciated: 'bg-blue-50 text-blue-700',
  disposed: 'bg-gray-100 text-gray-500',
  impaired: 'bg-amber-50 text-amber-700',
  draft: 'bg-yellow-50 text-yellow-700',
}

export default function AssetRegisterPage() {
  const { companyId } = useAppCtx()
  const [assets, setAssets] = useState<Asset[]>([])
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [selected, setSelected] = useState<Asset | null>(null)
  const [deprSchedule, setDeprSchedule] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const [{ data: faData }, { data: deprData }] = await Promise.all([
      supabase.from('fixed_assets').select(`
        id, asset_number, asset_name, description, category_id, acquisition_date,
        depreciation_start_date, acquisition_cost, salvage_value, useful_life_months,
        depreciation_method, serial_number, location, status,
        fixed_asset_categories!inner(category_name),
        branches(branch_name),
        departments(department_name)
      `).eq('company_id', companyId).order('asset_number'),
      supabase.from('asset_depreciation_entries')
        .select('asset_id, depreciation_amount, status')
        .eq('company_id', companyId).eq('status', 'posted'),
    ])

    const deprMap: Record<string, number> = {}
    for (const d of (deprData || [])) {
      deprMap[d.asset_id] = (deprMap[d.asset_id] || 0) + Number(d.depreciation_amount)
    }

    const list = (faData || []).map((a: any) => ({
      id: a.id,
      asset_number: a.asset_number,
      asset_name: a.asset_name,
      description: a.description,
      category_id: a.category_id,
      category_name: a.fixed_asset_categories?.category_name ?? '',
      branch_name: a.branches?.branch_name ?? null,
      department_name: a.departments?.department_name ?? null,
      acquisition_date: a.acquisition_date,
      depreciation_start_date: a.depreciation_start_date,
      acquisition_cost: Number(a.acquisition_cost),
      salvage_value: Number(a.salvage_value),
      useful_life_months: a.useful_life_months,
      depreciation_method: a.depreciation_method,
      serial_number: a.serial_number,
      location: a.location,
      status: a.status,
      accum_depr: deprMap[a.id] || 0,
      nbv: Number(a.acquisition_cost) - (deprMap[a.id] || 0),
    }))

    setAssets(list)
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  const openDetail = async (a: Asset) => {
    setSelected(a)
    const { data } = await supabase.from('asset_depreciation_entries')
      .select('*').eq('asset_id', a.id).order('period_number')
    setDeprSchedule(data || [])
  }

  const visible = assets.filter(a => {
    if (statusFilter !== 'all' && a.status !== statusFilter) return false
    const q = search.toLowerCase()
    return !q || a.asset_name.toLowerCase().includes(q) || a.asset_number.toLowerCase().includes(q) || (a.location || '').toLowerCase().includes(q)
  })

  if (selected) return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <button onClick={() => setSelected(null)} className="text-xs text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Detail — {selected.asset_number}</span>
        <span className={`ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${STATUS_COLOR[selected.status]}`}>
          {selected.status.replace(/_/g, ' ')}
        </span>
      </div>
      <div className="px-5 py-4 max-w-4xl space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Asset Information</p>
            {[
              ['Asset Number', selected.asset_number],
              ['Asset Name', selected.asset_name],
              ['Category', selected.category_name],
              ['Branch', selected.branch_name || '—'],
              ['Department', selected.department_name || '—'],
              ['Location', selected.location || '—'],
              ['Serial Number', selected.serial_number || '—'],
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between text-xs">
                <span className="text-gray-500 w-32">{k}</span>
                <span className="text-gray-900 font-medium text-right">{v}</span>
              </div>
            ))}
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Valuation</p>
            {[
              ['Acquisition Date', selected.acquisition_date],
              ['Depr. Start', selected.depreciation_start_date],
              ['Useful Life', `${selected.useful_life_months} months`],
              ['Method', METHODS[selected.depreciation_method] || selected.depreciation_method],
              ['Acquisition Cost', `₱ ${fmt(selected.acquisition_cost)}`],
              ['Salvage Value', `₱ ${fmt(selected.salvage_value)}`],
              ['Accum. Depreciation', `₱ ${fmt(selected.accum_depr)}`],
              ['Net Book Value', `₱ ${fmt(selected.nbv)}`],
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between text-xs">
                <span className="text-gray-500 w-40">{k}</span>
                <span className="text-gray-900 font-mono font-medium text-right">{v}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Depreciation Schedule</p>
          </div>
          <div className="overflow-y-auto max-h-72">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200 sticky top-0">
                <tr>{['Period','Date','Depr. Amount','Accum. Depr','NBV After','Status'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {deprSchedule.map(d => (
                  <tr key={d.id} className={`hover:bg-gray-50/60 ${d.status === 'posted' ? '' : d.status === 'skipped' ? 'opacity-40' : ''}`}>
                    <td className="px-3 py-1.5 font-mono text-gray-600">{d.period_number}</td>
                    <td className="px-3 py-1.5 font-mono text-gray-600">{d.entry_date}</td>
                    <td className="px-3 py-1.5 font-mono text-right text-gray-800">{fmt(d.depreciation_amount)}</td>
                    <td className="px-3 py-1.5 font-mono text-right text-gray-600">{fmt(d.accumulated_depr_after)}</td>
                    <td className="px-3 py-1.5 font-mono text-right font-semibold text-gray-900">{fmt(d.net_book_value_after)}</td>
                    <td className="px-3 py-1.5">
                      <span className={`inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium ${d.status === 'posted' ? 'bg-green-50 text-green-700' : d.status === 'skipped' ? 'bg-gray-100 text-gray-400' : 'bg-yellow-50 text-yellow-700'}`}>
                        {d.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Register</span>
      </div>
      <div className="px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2 flex-wrap">
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search by name, number, location…"
              className="border border-gray-200 rounded px-2.5 py-1 text-xs w-64 focus:outline-none focus:ring-1 focus:ring-gray-900" />
            <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
              className="border border-gray-200 rounded px-2.5 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Statuses</option>
              <option value="active">Active</option>
              <option value="fully_depreciated">Fully Depreciated</option>
              <option value="impaired">Impaired</option>
              <option value="disposed">Disposed</option>
              <option value="draft">Draft</option>
            </select>
            <span className="text-xs text-gray-400 ml-auto">{visible.length} records</span>
          </div>
          {loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading…</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Asset #','Name','Category','Acquired','Cost (₱)','Accum. Depr (₱)','NBV (₱)','Method','Status'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visible.length === 0 ? (
                    <tr><td colSpan={9} className="py-12 text-center text-gray-400">No assets found</td></tr>
                  ) : visible.map(a => (
                    <tr key={a.id} className="hover:bg-gray-50/60 cursor-pointer" onClick={() => openDetail(a)}>
                      <td className="px-3 py-2 font-mono font-semibold text-blue-700">{a.asset_number}</td>
                      <td className="px-3 py-2 text-gray-800 max-w-[160px] truncate">{a.asset_name}</td>
                      <td className="px-3 py-2 text-gray-500">{a.category_name}</td>
                      <td className="px-3 py-2 font-mono text-gray-500">{a.acquisition_date}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-800">{fmt(a.acquisition_cost)}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-500">{fmt(a.accum_depr)}</td>
                      <td className="px-3 py-2 text-right font-mono font-semibold text-gray-900">{fmt(a.nbv)}</td>
                      <td className="px-3 py-2 text-gray-500">{METHODS[a.depreciation_method] || a.depreciation_method}</td>
                      <td className="px-3 py-2">
                        <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${STATUS_COLOR[a.status]}`}>
                          {a.status.replace(/_/g, ' ')}
                        </span>
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
