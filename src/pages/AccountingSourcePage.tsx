import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { ArrowLeft, BookOpen, FileText, Route, Scale } from 'lucide-react'
import { supabase } from '@/lib/supabase'

type SourceTrace = {
  source_doc_type: string
  source_doc_id: string
  source_display_name: string
  source_number: string | null
  source_date: string | null
  source_status: string | null
  source_record: Record<string, unknown> | null
  module_route: string | null
  journal_route: string | null
  general_ledger_route: string | null
}

const hiddenFields = new Set(['company_id', 'created_by', 'updated_by'])
const humanize = (value: string) => value.replace(/_/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase())
const formatValue = (value: unknown) => {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (typeof value === 'number') return value.toLocaleString('en-PH', { maximumFractionDigits: 4 })
  if (typeof value === 'object') return JSON.stringify(value, null, 2)
  return String(value)
}

export default function AccountingSourcePage() {
  const [searchParams] = useSearchParams()
  const sourceType = (searchParams.get('sourceType') || '').trim().toUpperCase()
  const sourceId = searchParams.get('sourceId') || ''
  const [trace, setTrace] = useState<SourceTrace | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!sourceType || !sourceId) {
      setTrace(null)
      setError('A source type and source ID are required.')
      return
    }

    let alive = true
    const load = async () => {
      setLoading(true)
      setError('')
      const { data, error: rpcError } = await supabase.rpc('fn_get_accounting_trace', {
        p_source_doc_type: sourceType,
        p_source_doc_id: sourceId,
      })
      if (!alive) return
      if (rpcError) {
        setTrace(null)
        setError(rpcError.message)
      } else {
        setTrace(data as unknown as SourceTrace)
      }
      setLoading(false)
    }
    void load()
    return () => { alive = false }
  }, [sourceId, sourceType])

  const fields = Object.entries(trace?.source_record || {}).filter(([key]) => !hiddenFields.has(key))

  return (
    <div className="px-5 py-4 space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-gray-500" aria-hidden="true" />
            <h1 className="text-xl font-semibold text-gray-900">Accounting Source</h1>
          </div>
          <p className="text-sm text-gray-500 mt-1">Read-only source evidence behind a posted accounting trace</p>
        </div>
        <Link
          to={`/accounting-trace?sourceType=${encodeURIComponent(sourceType)}&sourceId=${encodeURIComponent(sourceId)}`}
          className="inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900"
        >
          <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
          Full trace
        </Link>
      </div>

      {error && <div className="border border-red-200 bg-red-50 rounded-md px-4 py-3 text-sm text-red-700">{error}</div>}
      {loading && <div className="bg-white border border-gray-200 rounded-lg p-12 text-center text-sm text-gray-400">Loading source evidence…</div>}

      {!loading && trace && (
        <>
          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between gap-4 flex-wrap">
              <div>
                <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Resolved Source</div>
                <div className="text-sm font-semibold text-gray-900 mt-0.5">
                  {trace.source_display_name} {trace.source_number || ''}
                </div>
              </div>
              <div className="flex items-center gap-4 flex-wrap">
                {trace.module_route && (
                  <Link to={trace.module_route} className="inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900">
                    <Route className="h-3.5 w-3.5" aria-hidden="true" />
                    Module
                  </Link>
                )}
                {trace.journal_route && (
                  <Link to={trace.journal_route} className="inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900">
                    <BookOpen className="h-3.5 w-3.5" aria-hidden="true" />
                    Journal entry
                  </Link>
                )}
                {trace.general_ledger_route && (
                  <Link to={trace.general_ledger_route} className="inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900">
                    <Scale className="h-3.5 w-3.5" aria-hidden="true" />
                    General ledger
                  </Link>
                )}
              </div>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-2 px-4 py-3 text-sm">
              <div><div className="text-[10px] uppercase tracking-wide text-gray-400">Type</div><div className="text-gray-800">{trace.source_doc_type}</div></div>
              <div><div className="text-[10px] uppercase tracking-wide text-gray-400">Status</div><div className="text-gray-800">{trace.source_status || '—'}</div></div>
              <div><div className="text-[10px] uppercase tracking-wide text-gray-400">Date</div><div className="text-gray-800">{trace.source_date || '—'}</div></div>
              <div><div className="text-[10px] uppercase tracking-wide text-gray-400">Source ID</div><div className="font-mono text-xs text-gray-700 break-all">{trace.source_doc_id}</div></div>
            </div>
          </section>

          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-2.5 border-b border-gray-100 bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">Source Record</div>
            <dl className="grid grid-cols-1 md:grid-cols-2">
              {fields.map(([key, value]) => (
                <div key={key} className="grid grid-cols-[minmax(8rem,0.45fr)_1fr] gap-3 px-4 py-2 border-b border-gray-100 text-xs">
                  <dt className="text-gray-400">{humanize(key)}</dt>
                  <dd className={`text-gray-700 break-words ${typeof value === 'object' && value !== null ? 'font-mono whitespace-pre-wrap' : ''}`}>{formatValue(value)}</dd>
                </div>
              ))}
              {fields.length === 0 && <div className="px-4 py-8 text-sm text-gray-400">No source fields were returned.</div>}
            </dl>
          </section>
        </>
      )}
    </div>
  )
}
