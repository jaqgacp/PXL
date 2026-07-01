import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { id: string; export_type: string; report_name: string; period_year: number | null; period_month: number | null; period_quarter: number | null; file_name: string; row_count: number; generated_at: string }

const TYPE_LABELS: Record<string, string> = { dat_file: 'DAT File', csv_export: 'CSV Export', report: 'Report' }
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']
const fmtPeriod = (r: Row) => r.period_month ? `${MONTHS[r.period_month - 1]} ${r.period_year}` : r.period_quarter ? `Q${r.period_quarter} ${r.period_year}` : r.period_year || '—'

export default function CASExportHistoryPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [filterType, setFilterType] = useState('')

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let query = supabase.from('cas_export_log').select('*').eq('company_id', companyId).order('generated_at', { ascending: false }).limit(200)
    if (filterType) query = query.eq('export_type', filterType)
    const { data } = await query
    setRows((data as Row[]) || [])
    setLoading(false)
  }, [companyId, filterType])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Export History</h1>
        <p className="text-sm text-gray-500 mt-0.5">Log of all DAT files, CSV exports &amp; reports generated from the system</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={filterType} onChange={e => setFilterType(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="">All Types</option>
          {Object.entries(TYPE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Generated</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Report</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">File</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rows</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No exports recorded yet.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-xs text-gray-500">{new Date(r.generated_at).toLocaleString('en-PH')}</td>
                  <td className="px-4 py-2 text-gray-600">{TYPE_LABELS[r.export_type] || r.export_type}</td>
                  <td className="px-4 py-2 text-gray-700">{r.report_name}</td>
                  <td className="px-4 py-2 text-gray-600">{fmtPeriod(r)}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono text-xs">{r.file_name}</td>
                  <td className="px-4 py-2 text-right text-gray-700">{r.row_count}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
