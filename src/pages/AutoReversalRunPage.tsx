import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

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
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Auto Reversal Run</span>
        <select value={filterPeriod} onChange={e => setFilterPeriod(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All periods</option>
          {periods.map(p => <option key={p.id} value={p.id}>{p.period_name}</option>)}
        </select>
        <label className="text-xs text-gray-500">Reversal Date</label>
        <input type="date" value={reversalDate} onChange={e => setReversalDate(e.target.value)}
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <button onClick={load} disabled={!companyId || loading}
          className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50 disabled:opacity-40">
          Refresh
        </button>
        {error && <span className="text-xs text-red-600">{error}</span>}
        {pendingJEs.length > 0 && (
          <button onClick={reverseAll} disabled={running}
            className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {running ? 'Reversing…' : `Execute All (${pendingJEs.length})`}
          </button>
        )}
      </div>

      <div className="px-5 py-4 space-y-4">
        {/* Info banner */}
        <div className="bg-blue-50 border border-blue-200 rounded-lg px-4 py-3 text-xs text-blue-700">
          Auto Reversal Run creates reversing journal entries for all posted JEs that were flagged with "Auto-reverse at next period start." Reversals will be posted to <strong>{reversalDate}</strong>. Ensure this date falls within an open fiscal period.
        </div>

        {/* KPI strip */}
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">JEs Awaiting Reversal</p>
            <p className="text-lg font-bold text-gray-900 tabular-nums">{pendingJEs.length}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total Amount (DR)</p>
            <p className="text-lg font-bold text-gray-900 tabular-nums font-mono">{fmt(totalDebit)}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Reversal Date</p>
            <p className="text-lg font-bold text-gray-700 font-mono">{reversalDate}</p>
          </div>
        </div>

        {/* Results */}
        {showResults && results.length > 0 && (
          <div className={`border rounded-lg overflow-hidden ${failed ? 'border-amber-200' : 'border-green-200'}`}>
            <div className={`px-4 py-2.5 border-b ${failed ? 'border-amber-200 bg-amber-50' : 'border-green-200 bg-green-50'}`}>
              <span className={`text-[10px] font-semibold uppercase tracking-wide ${failed ? 'text-amber-600' : 'text-green-600'}`}>
                Run Complete — {succeeded} reversed{failed ? `, ${failed} failed` : ''}
              </span>
            </div>
            <table className="w-full text-xs bg-white">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Original JE', 'Result', 'Reversal JE / Error'].map(hh => (
                    <th key={hh} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left">{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {results.map(r => (
                  <tr key={r.je_id} className={r.success ? '' : 'bg-red-50'}>
                    <td className="px-3 py-2 font-mono text-gray-900">{r.je_number}</td>
                    <td className="px-3 py-2">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${r.success ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
                        {r.success ? 'Reversed' : 'Failed'}
                      </span>
                    </td>
                    <td className="px-3 py-2 font-mono text-gray-600">{r.reversal_je || r.error || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Pending JEs */}
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
            <table className="w-full text-xs">
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
    </div>
  )
}
