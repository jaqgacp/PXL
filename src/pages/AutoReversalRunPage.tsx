import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type PendingJE = {
  id: string
  je_number: string
  je_date: string
  description: string | null
  total_debit: number
  fiscal_period_id: string | null
  period_name?: string
}

type RunResult = {
  je_id: string; je_number: string; success: boolean; reversal_je?: string; error?: string
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

function firstOfNextMonth(dateStr: string): string {
  const d = new Date(dateStr)
  d.setDate(1)
  d.setMonth(d.getMonth() + 1)
  return d.toISOString().split('T')[0]
}

export default function AutoReversalRunPage() {
  const { companyId } = useAppCtx()
  const [reversalDate, setReversalDate] = useState(firstOfNextMonth(today()))
  const [pendingJEs, setPendingJEs] = useState<PendingJE[]>([])
  const [periods, setPeriods] = useState<{ id: string; period_name: string }[]>([])
  const [filterPeriod, setFilterPeriod] = useState('')
  const [loading, setLoading] = useState(false)
  const [running, setRunning] = useState(false)
  const [results, setResults] = useState<RunResult[]>([])
  const [showResults, setShowResults] = useState(false)
  const [error, setError] = useState('')

  const loadPeriods = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('fiscal_periods').select('id,period_name')
      .eq('company_id', companyId).order('start_date', { ascending: false })
    setPeriods((data as any[]) || [])
  }, [companyId])

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true); setResults([]); setShowResults(false)
    let q = supabase.from('journal_entries')
      .select('id,je_number,je_date,description,total_debit,fiscal_period_id')
      .eq('company_id', companyId).eq('status', 'posted')
      .eq('auto_reverse', true).is('reversed_by_je_id', null)
      .order('je_date', { ascending: false })
    if (filterPeriod) q = q.eq('fiscal_period_id', filterPeriod)
    const { data } = await q
    const jes = (data as PendingJE[]) || []
    const periodMap: Record<string, string> = {}
    for (const p of periods) periodMap[p.id] = p.period_name
    setPendingJEs(jes.map(je => ({ ...je, period_name: je.fiscal_period_id ? periodMap[je.fiscal_period_id] : undefined })))
    setLoading(false)
  }, [companyId, filterPeriod, periods])

  useEffect(() => { if (companyId) loadPeriods() }, [loadPeriods, companyId])
  useEffect(() => { if (companyId) load() }, [load, companyId])

  const reverseOne = async (je: PendingJE) => {
    setRunning(true); setError('')
    const { data: revId, error: e } = await supabase.rpc('fn_reverse_je', {
      p_je_id: je.id, p_reversal_date: reversalDate,
    })
    if (e) { setError(e.message) }
    else {
      let rev_num: string | undefined
      if (revId) {
        const { data: revJe } = await supabase.from('journal_entries').select('je_number').eq('id', revId).maybeSingle()
        rev_num = (revJe as any)?.je_number
      }
      setResults(r => [...r, { je_id: je.id, je_number: je.je_number, success: true, reversal_je: rev_num }])
      setShowResults(true)
    }
    setRunning(false)
    await load()
  }

  const reverseAll = async () => {
    if (!pendingJEs.length) return
    setRunning(true); setError(''); setResults([])
    const res: RunResult[] = []
    for (const je of pendingJEs) {
      const { data: revId, error: e } = await supabase.rpc('fn_reverse_je', {
        p_je_id: je.id, p_reversal_date: reversalDate,
      })
      if (e) {
        res.push({ je_id: je.id, je_number: je.je_number, success: false, error: e.message })
      } else {
        let rev_num: string | undefined
        if (revId) {
          const { data: revJe } = await supabase.from('journal_entries').select('je_number').eq('id', revId).maybeSingle()
          rev_num = (revJe as any)?.je_number
        }
        res.push({ je_id: je.id, je_number: je.je_number, success: true, reversal_je: rev_num })
      }
    }
    setResults(res)
    setShowResults(true)
    setRunning(false)
    await load()
  }

  const totalDebit = pendingJEs.reduce((s, j) => s + Number(j.total_debit), 0)
  const failed = results.filter(r => !r.success).length
  const succeeded = results.filter(r => r.success).length

  return (
    <LegacyTransactionWorkspace title="Auto Reversal Run" family="journal" pattern="D" posting
      documentNo={reversalDate} status={showResults ? 'posted' : 'draft'} identity="Pending reversing journals"
      financialFacts={[{ label: 'Reversal Debit', value: fmt(totalDebit) }, { label: 'Reversal Credit', value: fmt(totalDebit) }, { label: 'Eligible Journals', value: pendingJEs.length }, { label: 'Successful Reversals', value: results.filter(result => result.success).length }]}
      contextFacts={[{ label: 'Reversal Date', value: reversalDate }, { label: 'Period Filter', value: periods.find(period => period.id === filterPeriod)?.period_name || 'All eligible periods' }, { label: 'Run State', value: running ? 'Posting' : showResults ? 'Completed' : 'Ready' }]}
      actions={[
        { key: 'refresh', label: loading ? 'Refreshing…' : 'Refresh', onClick: load, disabled: !companyId || loading },
        { key: 'execute', label: running ? 'Reversing…' : `Execute All (${pendingJEs.length})`, onClick: reverseAll, disabled: running || pendingJEs.length === 0, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Reversal Date', card: 0, content: <input type="date" value={reversalDate} onChange={event => setReversalDate(event.target.value)} className="pxl-input w-full" /> },
        { key: 'state', label: 'Run State', card: 0, content: <div className="pxl-readonly-field">{running ? 'Posting' : showResults ? 'Completed' : 'Ready'}</div> },
        { key: 'period', label: 'Period Filter', card: 1, span: 2, content: <select value={filterPeriod} onChange={event => setFilterPeriod(event.target.value)} className="pxl-input w-full"><option value="">All periods</option>{periods.map(period => <option key={period.id} value={period.id}>{period.period_name}</option>)}</select> },
        { key: 'basis', label: 'Posting Basis', card: 2, span: 2, content: <div className="pxl-readonly-field">Posted journals flagged for auto reversal</div> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}<div className="pxl-validation-message border border-gray-200">Reversals post only when the selected date is in an open period.</div></div>,
        activity: showResults && results.length ? <div className={`border rounded-lg overflow-hidden ${failed ? 'border-amber-200' : 'border-green-200'}`}><div className="px-3 py-2">Run complete — {succeeded} reversed{failed ? `, ${failed} failed` : ''}</div><table className="pxl-data-grid w-full"><thead><tr><th>Original JE</th><th>Result</th><th>Reversal JE / Error</th></tr></thead><tbody>{results.map(result => <tr key={result.je_id}><td>{result.je_number}</td><td>{result.success ? 'Reversed' : 'Failed'}</td><td>{result.reversal_je || result.error || '—'}</td></tr>)}</tbody></table></div> : undefined,
      }}>
    <div>
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Journal Entries Pending Auto-Reversal</span>
          </div>
          {loading ? (
            <div className="py-12 text-center text-sm text-gray-400">Loading…</div>
          ) : pendingJEs.length === 0 ? (
            <div className="py-14 text-center">
              <p className="text-sm font-medium text-gray-500">No journal entries pending auto-reversal</p>
              <p className="text-xs text-gray-400 mt-1">All auto-reverse flagged JEs have been reversed, or none exist for the selected filter.</p>
            </div>
          ) : (
            <table className="pxl-data-grid w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['JE Number', 'JE Date', 'Period', 'Description', 'Total Debit', ''].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${hh === 'Total Debit' ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {pendingJEs.map(je => (
                  <tr key={je.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{je.je_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{je.je_date}</td>
                    <td className="px-3 py-2 text-gray-500">{je.period_name || '—'}</td>
                    <td className="px-3 py-2 text-gray-700 max-w-[240px] truncate">{je.description || '—'}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-900">{fmt(Number(je.total_debit))}</td>
                    <td className="px-3 py-2 text-right">
                      <button onClick={() => reverseOne(je)} disabled={running}
                        className="text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-40">Reverse</button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t border-gray-200 bg-gray-50">
                <tr>
                  <td colSpan={4} className="px-3 py-2 text-right font-semibold text-gray-700">Total</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(totalDebit)}</td>
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
