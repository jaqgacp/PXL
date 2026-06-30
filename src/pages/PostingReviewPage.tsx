import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type JE = {
  id: string; je_number: string; je_date: string; description: string | null
  reference_doc_type: string | null; status: string; total_debit: number; total_credit: number
  is_auto_reversal: boolean
}
type Line = {
  id: string; je_id: string; line_number: number; account_id: string
  description: string | null; debit_amount: number; credit_amount: number
  chart_of_accounts: { account_code: string; account_name: string } | null
}
type PeriodRef = { id: string; period_name: string }

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const FILTER_GROUPS: Record<string, string[]> = {
  Manual: ['MANUAL'],
  Sales: ['SI', 'OR', 'CM', 'DM'],
  Purchasing: ['VB', 'PV', 'CP', 'VC'],
  Banking: ['FT', 'IBT', 'BADJ', 'PCV', 'PCR', 'CV'],
}

export default function PostingReviewPage() {
  const { companyId } = useAppCtx()
  const [periods, setPeriods] = useState<PeriodRef[]>([])
  const [periodId, setPeriodId] = useState('')
  const [refFilter, setRefFilter] = useState('All')
  const [search, setSearch] = useState('')

  const [entries, setEntries] = useState<JE[]>([])
  const [lines, setLines] = useState<Line[]>([])
  const [selected, setSelected] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const loadPeriods = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('fiscal_periods').select('id,period_name')
      .eq('company_id', companyId).order('start_date', { ascending: false })
    const per = (data as PeriodRef[]) || []
    setPeriods(per)
    if (per.length && !periodId) setPeriodId(per[0].id)
  }, [companyId, periodId])

  useEffect(() => { if (companyId) loadPeriods() }, [loadPeriods, companyId])

  const load = useCallback(async () => {
    if (!companyId || !periodId) { setEntries([]); setLines([]); return }
    setLoading(true)
    const { data: jeData } = await supabase.from('journal_entries')
      .select('id,je_number,je_date,description,reference_doc_type,status,total_debit,total_credit,is_auto_reversal')
      .eq('company_id', companyId).eq('fiscal_period_id', periodId)
      .order('je_date', { ascending: true }).order('je_number', { ascending: true })
    const jes = (jeData as JE[]) || []
    setEntries(jes)
    if (jes.length) {
      const { data: lineData } = await supabase.from('journal_entry_lines')
        .select('id,je_id,line_number,account_id,description,debit_amount,credit_amount,chart_of_accounts(account_code,account_name)')
        .in('je_id', jes.map(j => j.id)).order('line_number')
      setLines((lineData as any as Line[]) || [])
    } else {
      setLines([])
    }
    setSelected(null)
    setLoading(false)
  }, [companyId, periodId])

  useEffect(() => { if (companyId && periodId) load() }, [load, companyId, periodId])

  const filtered = entries.filter(e => {
    if (refFilter === 'Auto-Reversal') {
      if (!(e.is_auto_reversal || e.reference_doc_type === 'REV')) return false
    } else if (refFilter !== 'All') {
      if (!(FILTER_GROUPS[refFilter] || []).includes(e.reference_doc_type || '')) return false
    }
    if (search && !(e.je_number.toLowerCase().includes(search.toLowerCase()) || (e.description || '').toLowerCase().includes(search.toLowerCase()))) return false
    return true
  })

  const totalJEs = filtered.length
  const totalDebit = filtered.reduce((s, e) => s + e.total_debit, 0)
  const totalCredit = filtered.reduce((s, e) => s + e.total_credit, 0)
  const matched = Math.abs(totalDebit - totalCredit) <= 0.01

  const selLines = lines.filter(l => l.je_id === selected)
  const selJE = filtered.find(e => e.id === selected)

  const exportCSV = () => {
    const header = ['JE Number', 'Date', 'Ref Type', 'Status', 'Line #', 'Account Code', 'Account Name', 'Line Description', 'Debit', 'Credit']
    const csv = [header.join(',')]
    for (const e of filtered) {
      for (const l of lines.filter(x => x.je_id === e.id)) {
        csv.push([e.je_number, e.je_date, e.reference_doc_type || '', e.status, l.line_number,
          l.chart_of_accounts?.account_code || '', `"${(l.chart_of_accounts?.account_name || '').replace(/"/g, '""')}"`,
          `"${(l.description || '').replace(/"/g, '""')}"`, l.debit_amount.toFixed(2), l.credit_amount.toFixed(2)].join(','))
      }
    }
    const blob = new Blob([csv.join('\n')], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `PostingReview_${periodId}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Posting Review</span>
        <select value={periodId} onChange={e => setPeriodId(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          {periods.map(p => <option key={p.id} value={p.id}>{p.period_name}</option>)}
        </select>
        <select value={refFilter} onChange={e => setRefFilter(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          {['All', 'Manual', 'Sales', 'Purchasing', 'Banking', 'Auto-Reversal'].map(o => <option key={o} value={o}>{o}</option>)}
        </select>
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search JE # / description…"
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-48 focus:outline-none focus:ring-1 focus:ring-gray-900" />
        {filtered.length > 0 && (
          <button onClick={exportCSV} className="ml-auto px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Export CSV</button>
        )}
      </div>

      {/* Summary strip */}
      <div className="px-5 pt-4">
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total JEs</p>
            <p className="text-lg font-bold text-gray-900 tabular-nums">{totalJEs}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total Debit</p>
            <p className={`text-lg font-bold tabular-nums font-mono ${matched ? 'text-gray-900' : 'text-red-600'}`}>{fmt(totalDebit)}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total Credit</p>
            <p className={`text-lg font-bold tabular-nums font-mono ${matched ? 'text-gray-900' : 'text-red-600'}`}>{fmt(totalCredit)}</p>
          </div>
        </div>
      </div>

      <div className="px-5 py-4 space-y-4">
        {/* Master table */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
          {loading ? (
            <div className="py-12 text-center text-sm text-gray-400">Loading…</div>
          ) : filtered.length === 0 ? (
            <div className="py-12 text-center text-sm text-gray-400">No journal entries for this selection.</div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['JE Number', 'Date', 'Description', 'Ref Type', 'Total Debit', 'Total Credit', 'Status'].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Total Debit', 'Total Credit'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {filtered.map(e => (
                  <tr key={e.id} onClick={() => setSelected(e.id === selected ? null : e.id)}
                    className={`cursor-pointer ${selected === e.id ? 'bg-blue-50' : 'hover:bg-gray-50/60'}`}>
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{e.je_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{e.je_date}</td>
                    <td className="px-3 py-2 text-gray-700 max-w-[240px] truncate">{e.description || '—'}</td>
                    <td className="px-3 py-2 text-gray-500">{e.reference_doc_type || '—'}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(e.total_debit)}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(e.total_credit)}</td>
                    <td className="px-3 py-2">{e.status}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Detail panel */}
        {selJE && (
          <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
            <div className="px-4 py-2.5 border-b border-gray-100 flex items-center justify-between">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Lines — {selJE.je_number}</span>
              <span className={`text-xs font-medium ${Math.abs(selJE.total_debit - selJE.total_credit) <= 0.01 ? 'text-green-600' : 'text-red-600'}`}>
                {Math.abs(selJE.total_debit - selJE.total_credit) <= 0.01 ? 'Balanced ✓' : 'Unbalanced'}
              </span>
            </div>
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Account Code', 'Account Name', 'Line Description', 'Debit', 'Credit'].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Debit', 'Credit'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {selLines.map(l => (
                  <tr key={l.id}>
                    <td className="px-3 py-2 font-mono text-gray-900">{l.chart_of_accounts?.account_code || '—'}</td>
                    <td className="px-3 py-2 text-gray-700">{l.chart_of_accounts?.account_name || '—'}</td>
                    <td className="px-3 py-2 text-gray-500">{l.description || '—'}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{l.debit_amount ? fmt(l.debit_amount) : '—'}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{l.credit_amount ? fmt(l.credit_amount) : '—'}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t border-gray-200 bg-gray-50">
                <tr>
                  <td colSpan={3} className="px-3 py-2 text-right font-semibold text-gray-700">Totals</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(selJE.total_debit)}</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(selJE.total_credit)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
