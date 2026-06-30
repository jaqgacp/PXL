import { Fragment, useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type JE = {
  id: string; je_number: string; je_date: string; description: string | null
  reference_doc_type: string | null; reference_doc_id: string | null
  status: string; total_debit: number; total_credit: number
  is_auto_reversal: boolean; reversed_by_je_id: string | null
}

type Pair = { original: JE | null; reversal: JE | null }

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function ReversalReviewPage() {
  const { companyId } = useAppCtx()
  const [all, setAll] = useState<JE[]>([])
  const [loading, setLoading] = useState(false)
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [onlyUnmatched, setOnlyUnmatched] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('journal_entries')
      .select('id,je_number,je_date,description,reference_doc_type,reference_doc_id,status,total_debit,total_credit,is_auto_reversal,reversed_by_je_id')
      .eq('company_id', companyId)
      .or('status.eq.reversed,is_auto_reversal.eq.true,reference_doc_type.eq.REV')
      .order('je_date', { ascending: false })
    if (dateFrom) q = q.gte('je_date', dateFrom)
    if (dateTo) q = q.lte('je_date', dateTo)
    const { data } = await q
    setAll((data as JE[]) || [])
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  // Build pairs: original (has reversed_by_je_id) -> reversal
  const byId: Record<string, JE> = {}
  for (const j of all) byId[j.id] = j

  const pairs: Pair[] = []
  const used = new Set<string>()

  for (const j of all) {
    if (j.reference_doc_type === 'REV') continue // handled via its original
    if (j.reversed_by_je_id) {
      const rev = byId[j.reversed_by_je_id] || null
      pairs.push({ original: j, reversal: rev })
      used.add(j.id)
      if (rev) used.add(rev.id)
    } else if (j.status === 'reversed') {
      pairs.push({ original: j, reversal: null })
      used.add(j.id)
    }
  }
  // Reversal JEs whose original isn't in the set
  for (const j of all) {
    if (j.reference_doc_type === 'REV' && !used.has(j.id)) {
      const orig = j.reference_doc_id ? byId[j.reference_doc_id] || null : null
      pairs.push({ original: orig, reversal: j })
      used.add(j.id)
    }
  }

  const visible = onlyUnmatched ? pairs.filter(p => !p.original || !p.reversal) : pairs

  const renderRow = (je: JE, kind: 'original' | 'reversal', indented: boolean) => (
    <tr key={je.id} className="hover:bg-gray-50/60">
      <td className={`px-3 py-2 font-mono font-semibold text-gray-900 ${indented ? 'pl-8' : ''}`}>
        {indented && <span className="text-gray-300 mr-1">↳</span>}{je.je_number}
      </td>
      <td className="px-3 py-2 font-mono text-gray-500">{je.je_date}</td>
      <td className="px-3 py-2">
        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${kind === 'original' ? 'bg-amber-50 text-amber-700' : 'bg-red-50 text-red-700'}`}>
          {kind === 'original' ? 'REVERSED' : (je.is_auto_reversal ? 'AUTO REVERSAL' : 'REVERSAL')}
        </span>
      </td>
      <td className="px-3 py-2 text-gray-700 max-w-[260px] truncate">{je.description || '—'}</td>
      <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(je.total_debit)}</td>
      <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(je.total_credit)}</td>
      <td className="px-3 py-2 font-mono text-xs text-gray-400">
        {kind === 'original' ? (je.reversed_by_je_id ? (byId[je.reversed_by_je_id]?.je_number || je.reversed_by_je_id.slice(0, 8)) : '— none —')
          : (je.reference_doc_id ? (byId[je.reference_doc_id]?.je_number || je.reference_doc_id.slice(0, 8)) : '—')}
      </td>
    </tr>
  )

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Reversal Review</span>
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} title="From"
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} title="To"
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <label className="flex items-center gap-1.5 text-xs text-gray-600">
          <input type="checkbox" checked={onlyUnmatched} onChange={e => setOnlyUnmatched(e.target.checked)} /> Only unmatched
        </label>
      </div>

      <div className="px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
          {loading ? (
            <div className="py-16 text-center text-sm text-gray-400">Loading…</div>
          ) : visible.length === 0 ? (
            <div className="py-16 text-center text-sm text-gray-400">No reversals found.</div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['JE Number', 'Date', 'Type', 'Description', 'Total Debit', 'Total Credit', 'Linked JE'].map(hh => (
                    <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Total Debit', 'Total Credit'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {visible.map((p, i) => (
                  <Fragment key={p.original?.id || p.reversal?.id || i}>
                    {p.original && renderRow(p.original, 'original', false)}
                    {p.reversal && renderRow(p.reversal, 'reversal', !!p.original)}
                    {!p.reversal && p.original && (
                      <tr><td colSpan={7} className="px-3 py-1.5 pl-8 text-xs text-amber-600 italic">↳ Marked reversed but no reversing entry found</td></tr>
                    )}
                    {!p.original && p.reversal && (
                      <tr><td colSpan={7} className="px-3 py-1.5 text-xs text-amber-600 italic">Reversal with no matching original in range</td></tr>
                    )}
                  </Fragment>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  )
}
