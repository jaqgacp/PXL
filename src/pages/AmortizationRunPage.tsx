import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

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

export default function AmortizationRunPage() {
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
    const { data: schedules } = await supabase.from('amortization_schedules').select('id,schedule_name')
      .eq('company_id', companyId).eq('status', 'active')
    if (!schedules || schedules.length === 0) { setEntries([]); setLoading(false); return }
    const schedIds = schedules.map((s: any) => s.id)
    const schedMap: Record<string, string> = {}
    for (const s of schedules as any[]) schedMap[s.id] = s.schedule_name

    const { data: raw } = await supabase.from('amortization_entries')
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
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'AMORT', p_source_doc_id: entry.id })
      if (previewError) {
        results.push({ entry_id: entry.id, schedule_name: entry.schedule_name, period: entry.period_number, success: false, error: `Preview failed: ${previewError.message}` })
        continue
      }
      const { data: jeId, error: e } = await supabase.rpc('fn_post_amortization_entry', { p_entry_id: entry.id })
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
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'AMORT', p_source_doc_id: entry.id })
    if (previewError) {
      setError(`Amortization Entry is not ready to post: ${previewError.message}`)
      setRunning(false)
      return
    }
    const { error: e } = await supabase.rpc('fn_post_amortization_entry', { p_entry_id: entry.id })
    if (e) setError(e.message)
    setRunning(false)
    await load()
  }

  const totalDue = entries.reduce((s, e) => s + e.amount, 0)
  const failed = results.filter(r => !r.success).length
  const succeeded = results.filter(r => r.success).length

  return (
    <LegacyTransactionWorkspace title="Amortization Run" family="journal" pattern="D" posting
      documentNo={asOfDate} status={showResults ? 'posted' : 'draft'} identity="Due amortization entries"
      financialFacts={[{ label: 'Total Due', value: fmt(totalDue) }, { label: 'Due Entries', value: entries.length }, { label: 'Successful Posts', value: results.filter(result => result.success).length }, { label: 'Failed Posts', value: results.filter(result => !result.success).length }]}
      contextFacts={[{ label: 'Run Through', value: asOfDate }, { label: 'Run State', value: running ? 'Posting' : showResults ? 'Completed' : 'Ready' }]}
      sourceDocType="AMORT" sourceDocId={previewEntryId}
      actions={[
        { key: 'refresh', label: loading ? 'Refreshing…' : 'Refresh', onClick: load, disabled: !companyId || loading },
        { key: 'post', label: running ? 'Running…' : `Post All (${entries.length})`, onClick: runAll, disabled: running || entries.length === 0, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'through', label: 'Entries Due On or Before', card: 0, content: <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)} className="pxl-input w-full" /> },
        { key: 'state', label: 'Run State', card: 0, content: <div className="pxl-readonly-field">{running ? 'Posting' : showResults ? 'Completed' : 'Ready'}</div> },
        { key: 'basis', label: 'Posting Basis', card: 1, span: 2, content: <div className="pxl-readonly-field">Due amortization schedule entries</div> },
        { key: 'scope', label: 'Run Scope', card: 2, span: 2, content: <div className="pxl-readonly-field">{entries.length} pending entries</div> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}<div className="pxl-validation-message border border-gray-200">{entries.length ? `${entries.length} entries are ready for posting.` : 'No entries are currently due.'}</div></div>,
        gl: previewEntryId ? <GLImpactPanel companyId={companyId} sourceDocType="AMORT" sourceDocId={previewEntryId} previewRows={[]} /> : undefined,
        activity: showResults && results.length > 0 ? (
          <div className={`border rounded-lg overflow-hidden ${failed ? 'border-amber-200' : 'border-green-200'}`}>
            <div className={`px-4 py-2.5 border-b ${failed ? 'border-amber-200 bg-amber-50' : 'border-green-200 bg-green-50'}`}>
              <span className={`text-[10px] font-semibold uppercase tracking-wide ${failed ? 'text-amber-600' : 'text-green-600'}`}>
                Run Complete — {succeeded} posted{failed ? `, ${failed} failed` : ''}
              </span>
            </div>
            <table className="pxl-data-grid w-full bg-white">
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
                        {r.success ? 'Posted' : 'Failed'}
                      </span>
                    </td>
                    <td className="px-3 py-2 font-mono text-gray-600">{r.je_number || r.error || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : undefined,
      }}>
    <div>
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Pending Entries</span>
          </div>
          {loading ? (
            <div className="py-12 text-center text-sm text-gray-400">Loading…</div>
          ) : entries.length === 0 ? (
            <div className="py-14 text-center">
              <p className="text-sm font-medium text-gray-500">No pending amortization entries</p>
              <p className="text-xs text-gray-400 mt-1">All entries up to {asOfDate} are posted, or no active schedules exist.</p>
            </div>
          ) : (
            <table className="pxl-data-grid w-full">
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
                        className="text-xs font-medium text-blue-600 hover:text-blue-800 disabled:opacity-40">Post</button>
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
    </div>
    </LegacyTransactionWorkspace>
  )
}
