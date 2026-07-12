import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  number_series_id: string
  document_code: string
  document_name: string | null
  branch_name: string | null
  prefix: string | null
  suffix: string | null
  atp_series_start: number
  atp_series_end: number
  current_sequence: number
  numbers_remaining: number
  reserved_count: number
  issued_count: number
  voided_count: number
  total_allocated_count: number
  usage_percent: number
  is_exhausted: boolean
  at_or_below_alert_threshold: boolean
}

export default function CASATPUsageLogPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const run = useCallback(async () => {
    if (!companyId) {
      setRows([])
      return
    }
    setLoading(true)
    setError('')
    const { data, error: queryError } = await supabase
      .from('vw_cas_atp_usage')
      .select('*')
      .eq('company_id', companyId)
      .not('atp_series_start', 'is', null)
      .not('atp_series_end', 'is', null)
      .order('document_code')

    if (queryError) {
      setRows([])
      setError(queryError.message)
    } else {
      setRows((data as Row[]) || [])
    }
    setLoading(false)
  }, [companyId])

  useEffect(() => { run() }, [run])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">ATP Usage Log</h1>
        <p className="text-sm text-gray-500 mt-0.5">Authority To Print range consumption from immutable document-number issuance evidence</p>
      </div>

      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}

      <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                {['Document Type', 'Branch', 'ATP Range', 'Current', 'Reserved', 'Issued', 'Void / Gap', 'Remaining', 'Usage', 'Status'].map(label => (
                  <th key={label} className={`px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap ${['ATP Range', 'Current', 'Reserved', 'Issued', 'Void / Gap', 'Remaining', 'Usage'].includes(label) ? 'text-right' : 'text-left'}`}>{label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={10} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No ATP-authorized number series configured.'}</td></tr>
              ) : rows.map(row => (
                <tr key={row.number_series_id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-900 font-medium whitespace-nowrap">
                    {row.document_name || row.document_code}
                    <span className="ml-1 text-gray-400 font-mono text-xs">({row.document_code})</span>
                  </td>
                  <td className="px-4 py-2.5 text-gray-600">{row.branch_name || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{row.atp_series_start}–{row.atp_series_end}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{row.current_sequence}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-amber-700">{row.reserved_count}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{row.issued_count}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{row.voided_count}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{row.numbers_remaining}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{Number(row.usage_percent).toFixed(1)}%</td>
                  <td className="px-4 py-2.5">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${row.is_exhausted ? 'bg-red-50 text-red-700' : row.at_or_below_alert_threshold ? 'bg-amber-50 text-amber-700' : 'bg-green-50 text-green-700'}`}>
                      {row.is_exhausted ? 'Exhausted' : row.at_or_below_alert_threshold ? 'Low — Renew Soon' : 'OK'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
