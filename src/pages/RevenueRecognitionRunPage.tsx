import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'

type DueEntry = {
  id: string
  period_number: number
  entry_date: string
  amount: number
  status: 'pending' | 'posted' | 'skipped'
  schedule_id: string
  schedule_name: string
}

type RunResult = { entry_id: string; schedule_name: string; period: number; success: boolean; je_number?: string; error?: string }

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

export default function RevenueRecognitionRunPage() {
  const { companyId } = useAppCtx()
  const [asOfDate, setAsOfDate] = useState(today())
  const [entries, setEntries] = useState<DueEntry[]>([])
  const [loading, setLoading] = useState(false)
  const [running, setRunning] = useState(false)
  const [results, setResults] = useState<RunResult[]>([])
  const [showResults, setShowResults] = useState(false)
  const [error, setError] = useState('')
  const [previewEntryId, setPreviewEntryId] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true); setResults([]); setShowResults(false)
    const { data: schedules } = await supabase.from('revenue_recognition_schedules').select('id,schedule_name')
      .eq('company_id', companyId).eq('status', 'active')
    if (!schedules || schedules.length === 0) { setEntries([]); setLoading(false); return }
    const schedIds = (schedules as any[]).map(s => s.id)
    const schedMap: Record<string, string> = {}
    for (const s of schedules as any[]) schedMap[s.id] = s.schedule_name

    const { data: raw } = await supabase.from('revenue_recognition_entries')
      .select('id,period_number,entry_date,amount,status,schedule_id')
      .in('schedule_id', schedIds).eq('status', 'pending').lte('entry_date', asOfDate)
      .order('entry_date').order('schedule_id')
    const rows: DueEntry[] = (raw as any[] || []).map(r => ({
      ...r, schedule_name: schedMap[r.schedule_id] || r.schedule_id,
    }))
    setEntries(rows)
    setLoading(false)
  }, [companyId, asOfDate])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const runAll = async () => {
    if (!entries.length) return
    setRunning(true); setError(''); setResults([])
    const results: RunResult[] = []
    for (const entry of entries) {
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'REVREC', p_source_doc_id: entry.id })
      if (previewError) {
        results.push({ entry_id: entry.id, schedule_name: entry.schedule_name, period: entry.period_number, success: false, error: `Preview failed: ${previewError.message}` })
        continue
      }
      const { data: jeId, error: e } = await supabase.rpc('fn_post_revenue_recognition_entry', { p_entry_id: entry.id })
      if (e) {
        results.push({ entry_id: entry.id, schedule_name: entry.schedule_name, period: entry.period_number, success: false, error: e.message })
      } else {
        let je_number: string | undefined
        if (jeId) {
          const { data: je } = await supabase.from('journal_entries').select('je_number').eq('id', jeId).maybeSingle()
          je_number = (je as any)?.je_number
        }
        results.push({ entry_id: entry.id, schedule_name: entry.schedule_name, period: entry.period_number, success: true, je_number })
      }
    }
    setResults(results)
    setShowResults(true)
    setRunning(false)
    await load()
  }

  const runSingle = async (entry: DueEntry) => {
    setRunning(true); setError('')
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'REVREC', p_source_doc_id: entry.id })
    if (previewError) {
      setError(`Revenue Recognition Entry is not ready to post: ${previewError.message}`)
      setRunning(false)
      return
    }
    const { error: e } = await supabase.rpc('fn_post_revenue_recognition_entry', { p_entry_id: entry.id })
    if (e) setError(e.message)
    setRunning(false)
    await load()
  }

  const totalDue = entries.reduce((s, e) => s + e.amount, 0)
  const failed = results.filter(r => !r.success).length
  const succeeded = results.filter(r => r.success).length

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Revenue Recognition Run</span>
        <label className="text-xs text-gray-500">Entries due on or before</label>
        <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)}
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <button onClick={load} disabled={!companyId || loading}
          className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50 disabled:opacity-40">
          Refresh
        </button>
        {error && <span className="text-xs text-red-600">{error}</span>}
        {entries.length > 0 && (
          <button onClick={runAll} disabled={running}
            className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {running ? 'Running…' : `Recognize All (${entries.length})`}
          </button>
        )}
      </div>

      <div className="px-5 py-4 space-y-4">
        {/* KPI strip */}
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Entries Due</p>
            <p className="text-lg font-bold text-gray-900 tabular-nums">{entries.length}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total Revenue to Recognize</p>
            <p className="text-lg font-bold text-gray-900 tabular-nums font-mono">{fmt(totalDue)}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">As Of Date</p>
            <p className="text-lg font-bold text-gray-700 font-mono">{asOfDate}</p>
          </div>
        </div>

        {/* Run results */}
        {showResults && results.length > 0 && (
          <div className={`border rounded-lg overflow-hidden ${failed ? 'border-amber-200' : 'border-green-200'}`}>
            <div className={`px-4 py-2.5 border-b ${failed ? 'border-amber-200 bg-amber-50' : 'border-green-200 bg-green-50'}`}>
              <span className={`text-[10px] font-semibold uppercase tracking-wide ${failed ? 'text-amber-600' : 'text-green-600'}`}>
                Run Complete — {succeeded} posted{failed ? `, ${failed} failed` : ''}
              </span>
            </div>
            <table className="w-full text-xs bg-white">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Schedule', 'Period', 'Result', 'JE Number / Error'].map(hh => (
                    <th key={hh} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left">{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {results.map(r => (
                  <tr key={r.entry_id} className={r.success ? '' : 'bg-red-50'}>
                    <td className="px-3 py-2 text-gray-700">{r.schedule_name}</td>
                    <td className="px-3 py-2 font-mono text-gray-600">{r.period}</td>
                    <td className="px-3 py-2">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${r.success ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
                        {r.success ? 'Recognized' : 'Failed'}
                      </span>
                    </td>
                    <td className="px-3 py-2 font-mono text-gray-600">{r.je_number || r.error || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Due entries */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Pending Recognition Entries</span>
          </div>
          {loading ? (
            <div className="py-12 text-center text-sm text-gray-400">Loading…</div>
          ) : entries.length === 0 ? (
            <div className="py-14 text-center">
              <p className="text-sm font-medium text-gray-500">No pending recognition entries</p>
              <p className="text-xs text-gray-400 mt-1">All entries up to {asOfDate} are posted, or no active schedules exist.</p>
            </div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Schedule', 'Period', 'Entry Date', 'Amount', ''].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${hh === 'Amount' ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {entries.map(e => (
                  <tr key={e.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-medium text-gray-900">{e.schedule_name}</td>
                    <td className="px-3 py-2 font-mono text-gray-600">{e.period_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-700">{e.entry_date}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-900">{fmt(e.amount)}</td>
                    <td className="px-3 py-2 text-right whitespace-nowrap">
                      <button onClick={() => setPreviewEntryId(e.id)} disabled={running}
                        className="text-xs font-medium text-gray-600 hover:text-gray-900 disabled:opacity-40 mr-3">Preview</button>
                      <button onClick={() => runSingle(e)} disabled={running}
                        className="text-xs font-medium text-purple-600 hover:text-purple-800 disabled:opacity-40">Recognize</button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t border-gray-200 bg-gray-50">
                <tr>
                  <td colSpan={3} className="px-3 py-2 text-right font-semibold text-gray-700">Total</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(totalDue)}</td>
                  <td />
                </tr>
              </tfoot>
            </table>
          )}
        </div>
        {previewEntryId && (
          <GLImpactPanel companyId={companyId} sourceDocType="REVREC" sourceDocId={previewEntryId} previewRows={[]} />
        )}
      </div>
    </div>
  )
}
