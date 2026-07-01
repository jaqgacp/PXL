import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  branch_id: string
  prefix: string | null
  next_number: number
  atp_series_start: number | null
  atp_series_end: number | null
  atp_alert_threshold: number | null
  ref_document_types: { document_name: string; document_code: string } | null
  branches: { branch_name: string } | null
}

export default function CASATPUsageLogPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('number_series')
      .select('id,branch_id,prefix,next_number,atp_series_start,atp_series_end,atp_alert_threshold,ref_document_types(document_name,document_code),branches(branch_name)')
      .eq('company_id', companyId).not('atp_series_start', 'is', null).order('prefix')
    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">ATP Usage Log</h1>
        <p className="text-sm text-gray-500 mt-0.5">Authority To Print series consumption — pre-printed receipt/invoice ranges</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Document Type</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATP Range</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Current No.</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Used</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Remaining</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No ATP-registered number series configured.'}</td></tr>
              ) : rows.map(r => {
                const start = r.atp_series_start || 0
                const end = r.atp_series_end || 0
                const rangeSize = end - start + 1
                const used = Math.max(0, r.next_number - start)
                const remaining = Math.max(0, end - r.next_number + 1)
                const pctUsed = rangeSize > 0 ? (used / rangeSize) * 100 : 0
                const isAlert = r.atp_alert_threshold != null && remaining <= r.atp_alert_threshold
                const isExhausted = remaining <= 0
                return (
                  <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="px-4 py-2.5 text-gray-900 font-medium">{r.ref_document_types?.document_name || '—'} <span className="text-gray-400 font-mono text-xs">({r.prefix || r.ref_document_types?.document_code})</span></td>
                    <td className="px-4 py-2.5 text-gray-600">{r.branches?.branch_name || '—'}</td>
                    <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{start}–{end}</td>
                    <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{r.next_number}</td>
                    <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{used} ({pctUsed.toFixed(0)}%)</td>
                    <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{remaining}</td>
                    <td className="px-4 py-2.5">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${isExhausted ? 'bg-red-50 text-red-700' : isAlert ? 'bg-amber-50 text-amber-700' : 'bg-green-50 text-green-700'}`}>
                        {isExhausted ? 'Exhausted' : isAlert ? 'Low — Renew Soon' : 'OK'}
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
