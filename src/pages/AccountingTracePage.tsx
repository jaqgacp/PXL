import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  BookOpen,
  CalendarDays,
  FileText,
  RefreshCw,
  Route,
  Scale,
  Search,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import type { ServerGLImpact } from '@/components/GLImpactPanel'

type AuditEvent = {
  id: string
  action: string
  changed_by: string | null
  changed_at: string
}

type AccountingTrace = {
  source_doc_type: string
  source_doc_id: string | null
  source_display_name: string
  source_number: string | null
  source_date: string | null
  source_status: string | null
  source_route: string | null
  journal_entry_id: string | null
  journal_route: string | null
  general_ledger_route: string | null
  gl_impact: ServerGLImpact | null
  audit_events: AuditEvent[]
}

type ReportTraceRow = {
  report_family: string
  report_record_id: string
  source_doc_type: string
  source_doc_id: string
  journal_entry_id: string | null
  source_number: string | null
  source_date: string | null
  source_route: string | null
  module_route: string | null
  accounting_trace_route: string | null
  journal_route: string | null
  general_ledger_route: string | null
  trace_context: Record<string, unknown> | null
}

type ReportTraceRpcClient = {
  rpc: (
    fn: 'fn_get_report_trace_set',
    args: {
      p_company_id: string
      p_report_family: string
      p_filters: Record<string, string>
    },
  ) => PromiseLike<{
    data: ReportTraceRow[] | null
    error: { message: string } | null
  }>
}

const REPORT_CONTROL_PARAMS = new Set(['companyId', 'reportFamily', 'sourceType', 'sourceId', 'jeId'])

const getReportFilters = (params: URLSearchParams) => {
  const filters: Record<string, string> = {}
  for (const [key, value] of params.entries()) {
    if (!REPORT_CONTROL_PARAMS.has(key) && value.trim()) filters[key] = value.trim()
  }
  return filters
}

const humanize = (value: string) => value
  .replace(/[_-]+/g, ' ')
  .replace(/\b\w/g, character => character.toUpperCase())

const formatContextValue = (value: unknown) => {
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  return JSON.stringify(value)
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const formatDateTime = (value: string) => new Date(value).toLocaleString('en-PH')

export default function AccountingTracePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const sourceType = searchParams.get('sourceType') || ''
  const sourceId = searchParams.get('sourceId') || ''
  const jeId = searchParams.get('jeId') || ''
  const companyId = searchParams.get('companyId') || ''
  const reportFamily = searchParams.get('reportFamily') || ''
  const isReportMode = Boolean(companyId || reportFamily)
  const hasMixedTraceTargets = isReportMode && Boolean(jeId || sourceType || sourceId)
  const reportFilters = getReportFilters(searchParams)
  const reportFiltersKey = JSON.stringify(reportFilters)

  const [sourceTypeInput, setSourceTypeInput] = useState(sourceType)
  const [sourceIdInput, setSourceIdInput] = useState(sourceId)
  const [jeIdInput, setJeIdInput] = useState(jeId)
  const [trace, setTrace] = useState<AccountingTrace | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [reportRows, setReportRows] = useState<ReportTraceRow[]>([])
  const [reportLoading, setReportLoading] = useState(false)
  const [reportError, setReportError] = useState('')
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    setSourceTypeInput(sourceType)
    setSourceIdInput(sourceId)
    setJeIdInput(jeId)
  }, [jeId, sourceId, sourceType])

  useEffect(() => {
    if (isReportMode || (!jeId && !(sourceType && sourceId))) {
      setTrace(null)
      setError('')
      setLoading(false)
      return
    }

    let alive = true
    const load = async () => {
      setLoading(true)
      setError('')
      const { data, error: rpcError } = await supabase.rpc('fn_get_accounting_trace', {
        p_source_doc_type: sourceType || undefined,
        p_source_doc_id: sourceId || undefined,
        p_journal_entry_id: jeId || undefined,
      })
      if (!alive) return
      if (rpcError) {
        setTrace(null)
        setError(rpcError.message)
      } else {
        setTrace(data as unknown as AccountingTrace)
      }
      setLoading(false)
    }
    void load()
    return () => { alive = false }
  }, [isReportMode, jeId, reloadKey, sourceId, sourceType])

  useEffect(() => {
    if (!isReportMode) {
      setReportRows([])
      setReportError('')
      setReportLoading(false)
      return
    }
    if (hasMixedTraceTargets) {
      setReportRows([])
      setReportError('Report and direct journal/source trace parameters cannot be combined.')
      setReportLoading(false)
      return
    }
    if (!companyId || !reportFamily) {
      setReportRows([])
      setReportError('Both companyId and reportFamily are required for a report trace.')
      setReportLoading(false)
      return
    }

    let alive = true
    const load = async () => {
      setReportLoading(true)
      setReportError('')
      try {
        // The migration that adds this RPC is newer than the checked-in generated types.
        const client = supabase as unknown as ReportTraceRpcClient
        const { data, error: rpcError } = await client.rpc('fn_get_report_trace_set', {
          p_company_id: companyId,
          p_report_family: reportFamily,
          p_filters: JSON.parse(reportFiltersKey) as Record<string, string>,
        })
        if (!alive) return
        if (rpcError) {
          setReportRows([])
          setReportError(rpcError.message)
        } else {
          setReportRows(data || [])
        }
      } catch (loadError) {
        if (!alive) return
        setReportRows([])
        setReportError(loadError instanceof Error ? loadError.message : 'Unexpected report trace error')
      } finally {
        if (alive) setReportLoading(false)
      }
    }
    void load()
    return () => { alive = false }
  }, [companyId, hasMixedTraceTargets, isReportMode, reloadKey, reportFamily, reportFiltersKey])

  const submit = (event: FormEvent) => {
    event.preventDefault()
    const params = new URLSearchParams()
    if (jeIdInput.trim()) {
      params.set('jeId', jeIdInput.trim())
    } else if (sourceTypeInput.trim() && sourceIdInput.trim()) {
      params.set('sourceType', sourceTypeInput.trim().toUpperCase())
      params.set('sourceId', sourceIdInput.trim())
    }
    setSearchParams(params)
  }

  const impact = trace?.gl_impact

  if (isReportMode) {
    const contextEntries = (row: ReportTraceRow) => Object.entries(row.trace_context || {})
      .filter(([, value]) => value !== null && value !== undefined && value !== '')

    return (
      <div className="px-5 py-4 space-y-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <Route className="h-5 w-5 text-gray-500" aria-hidden="true" />
              <h1 className="text-xl font-semibold text-gray-900">Accounting Trace</h1>
            </div>
            <p className="text-sm text-gray-500 mt-1">Read-only contributing sources for {reportFamily ? humanize(reportFamily) : 'this report'}</p>
          </div>
          {companyId && reportFamily && (
            <button
              type="button"
              onClick={() => setReloadKey(key => key + 1)}
              disabled={reportLoading}
              className="inline-flex h-9 w-9 items-center justify-center border border-gray-300 rounded-md text-gray-600 hover:bg-gray-50 disabled:opacity-50"
              title="Reload report trace"
              aria-label="Reload report trace"
            >
              <RefreshCw className={`h-4 w-4 ${reportLoading ? 'animate-spin' : ''}`} aria-hidden="true" />
            </button>
          )}
        </div>

        <section className="bg-white border border-gray-200 rounded-lg px-4 py-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Report Selection</div>
          <dl className="mt-2 flex flex-wrap gap-x-6 gap-y-2 text-xs">
            <div className="min-w-0">
              <dt className="text-gray-400">Company</dt>
              <dd className="mt-0.5 font-mono text-gray-700 break-all">{companyId || 'Missing'}</dd>
            </div>
            <div>
              <dt className="text-gray-400">Family</dt>
              <dd className="mt-0.5 font-medium text-gray-800">{reportFamily ? humanize(reportFamily) : 'Missing'}</dd>
            </div>
            {Object.entries(reportFilters).map(([key, value]) => (
              <div key={key} className="min-w-0">
                <dt className="text-gray-400">{humanize(key)}</dt>
                <dd className="mt-0.5 font-mono text-gray-700 break-all">{value}</dd>
              </div>
            ))}
          </dl>
        </section>

        {reportError && (
          <div className="border border-red-200 bg-red-50 rounded-md px-4 py-3 text-sm text-red-700">
            Report trace could not be resolved: {reportError}
          </div>
        )}

        {reportLoading ? (
          <div className="bg-white border border-gray-200 rounded-lg divide-y divide-gray-100 animate-pulse">
            {[...Array(4)].map((_, index) => <div key={index} className="h-16 bg-gray-50/50" />)}
          </div>
        ) : !reportError && reportRows.length === 0 ? (
          <div className="bg-white border border-gray-200 rounded-lg py-16 text-center">
            <FileText className="h-6 w-6 text-gray-300 mx-auto" aria-hidden="true" />
            <p className="mt-2 text-sm text-gray-500">No contributing accounting sources were found for this report selection.</p>
          </div>
        ) : reportRows.length > 0 ? (
          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between gap-4">
              <div>
                <h2 className="text-sm font-semibold text-gray-900">Contributing Sources</h2>
                <p className="text-xs text-gray-500 mt-0.5">Source documents and posted accounting evidence included by the report filters.</p>
              </div>
              <span className="text-xs text-gray-400 whitespace-nowrap">{reportRows.length} {reportRows.length === 1 ? 'source' : 'sources'}</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[980px] text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Source', 'Date', 'Journal Entry', 'Context', 'Evidence'].map(header => (
                      <th key={header} className="px-3 py-2 text-left text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{header}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {reportRows.map((row, index) => {
                    const context = contextEntries(row)
                    return (
                      <tr key={`${row.report_record_id}-${row.source_doc_type}-${row.source_doc_id}-${row.journal_entry_id || index}`} className="align-top">
                        <td className="px-3 py-3">
                          <div className="flex items-center gap-2">
                            <span className="inline-flex rounded bg-gray-100 px-1.5 py-0.5 font-semibold text-gray-600">{row.source_doc_type}</span>
                            <span className="font-medium text-gray-900">{row.source_number || 'Unnumbered source'}</span>
                          </div>
                          <div className="mt-1 font-mono text-[10px] text-gray-400" title={row.source_doc_id}>{row.source_doc_id}</div>
                        </td>
                        <td className="px-3 py-3 text-gray-600 whitespace-nowrap">{row.source_date || 'Not available'}</td>
                        <td className="px-3 py-3">
                          {row.journal_entry_id ? (
                            <span className="font-mono text-[11px] text-gray-600" title={row.journal_entry_id}>{row.journal_entry_id}</span>
                          ) : <span className="text-gray-400">Not posted</span>}
                        </td>
                        <td className="px-3 py-3 text-gray-500">
                          {context.length > 0 ? (
                            <dl className="space-y-1">
                              {context.map(([key, value]) => (
                                <div key={key} className="flex gap-1.5">
                                  <dt className="text-gray-400 whitespace-nowrap">{humanize(key)}:</dt>
                                  <dd className="font-mono text-[10px] break-all">{formatContextValue(value)}</dd>
                                </div>
                              ))}
                            </dl>
                          ) : <span className="text-gray-400">—</span>}
                        </td>
                        <td className="px-3 py-3">
                          <div className="flex items-center gap-x-3 gap-y-2 flex-wrap whitespace-nowrap">
                            {row.accounting_trace_route && (
                              <Link to={row.accounting_trace_route} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                                <Route className="h-3.5 w-3.5" aria-hidden="true" /> Accounting Trace
                              </Link>
                            )}
                            {row.source_route && (
                              <Link to={row.source_route} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                                <FileText className="h-3.5 w-3.5" aria-hidden="true" /> Source
                              </Link>
                            )}
                            {row.journal_route && (
                              <Link to={row.journal_route} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                                <BookOpen className="h-3.5 w-3.5" aria-hidden="true" /> Journal
                              </Link>
                            )}
                            {row.general_ledger_route && (
                              <Link to={row.general_ledger_route} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                                <Scale className="h-3.5 w-3.5" aria-hidden="true" /> GL
                              </Link>
                            )}
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </section>
        ) : null}
      </div>
    )
  }

  return (
    <div className="px-5 py-4 space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <Route className="h-5 w-5 text-gray-500" aria-hidden="true" />
            <h1 className="text-xl font-semibold text-gray-900">Accounting Trace</h1>
          </div>
          <p className="text-sm text-gray-500 mt-1">Source document, journal entry, ledger lines, and audit evidence</p>
        </div>
        {(jeId || (sourceType && sourceId)) && (
          <button
            type="button"
            onClick={() => setReloadKey(key => key + 1)}
            disabled={loading}
            className="inline-flex h-9 w-9 items-center justify-center border border-gray-300 rounded-md text-gray-600 hover:bg-gray-50 disabled:opacity-50"
            title="Reload accounting trace"
            aria-label="Reload accounting trace"
          >
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" />
          </button>
        )}
      </div>

      <form onSubmit={submit} className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-end gap-3 flex-wrap">
        <div className="flex flex-col gap-1">
          <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Journal Entry ID</label>
          <input
            value={jeIdInput}
            onChange={event => setJeIdInput(event.target.value)}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-72 max-w-full focus:outline-none focus:ring-1 focus:ring-gray-900"
            placeholder="JE UUID"
          />
        </div>
        <div className="text-xs text-gray-400 pb-2">or</div>
        <div className="flex flex-col gap-1">
          <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Source Type</label>
          <input
            value={sourceTypeInput}
            onChange={event => setSourceTypeInput(event.target.value.toUpperCase())}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-32 focus:outline-none focus:ring-1 focus:ring-gray-900"
            placeholder="SI, OR, VB..."
          />
        </div>
        <div className="flex flex-col gap-1">
          <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Source ID</label>
          <input
            value={sourceIdInput}
            onChange={event => setSourceIdInput(event.target.value)}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-72 max-w-full focus:outline-none focus:ring-1 focus:ring-gray-900"
            placeholder="Source UUID"
          />
        </div>
        <button
          type="submit"
          disabled={!jeIdInput.trim() && !(sourceTypeInput.trim() && sourceIdInput.trim())}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40"
        >
          <Search className="h-4 w-4" aria-hidden="true" />
          Resolve
        </button>
      </form>

      {error && (
        <div className="border border-red-200 bg-red-50 rounded-md px-4 py-3 text-sm text-red-700">
          Accounting trace could not be resolved: {error}
        </div>
      )}

      {loading ? (
        <div className="bg-white border border-gray-200 rounded-lg divide-y divide-gray-100 animate-pulse">
          {[...Array(4)].map((_, index) => <div key={index} className="h-16 bg-gray-50/50" />)}
        </div>
      ) : !trace && !error ? (
        <div className="py-20 text-center text-sm text-gray-400">Enter a journal entry ID or source identifier.</div>
      ) : trace ? (
        <>
          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between gap-4 flex-wrap">
              <div>
                <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Resolved Source</div>
                <div className="text-sm font-semibold text-gray-900 mt-0.5">
                  {trace.source_display_name} {trace.source_number || ''}
                </div>
              </div>
              <div className="flex items-center gap-x-4 gap-y-2 flex-wrap">
                {trace.source_route && (
                  <Link to={trace.source_route} className="inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900">
                    <FileText className="h-3.5 w-3.5" aria-hidden="true" />
                    Source
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

            <div className="grid grid-cols-1 md:grid-cols-[1fr_auto_1fr_auto_1fr] items-stretch">
              <div className="px-4 py-4">
                <div className="flex items-center gap-2 text-xs font-semibold text-gray-900">
                  <FileText className="h-4 w-4 text-gray-500" aria-hidden="true" />
                  Source document
                </div>
                <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                  <dt className="text-gray-400">Type</dt><dd className="text-gray-700">{trace.source_doc_type}</dd>
                  <dt className="text-gray-400">Status</dt><dd className="text-gray-700">{trace.source_status || 'Not available'}</dd>
                  <dt className="text-gray-400">Date</dt><dd className="text-gray-700">{trace.source_date || 'Not available'}</dd>
                </dl>
              </div>
              <div className="hidden md:flex items-center text-gray-300"><span>→</span></div>
              <div className="px-4 py-4 border-t md:border-t-0 md:border-l border-gray-100">
                <div className="flex items-center gap-2 text-xs font-semibold text-gray-900">
                  <BookOpen className="h-4 w-4 text-gray-500" aria-hidden="true" />
                  Journal entry
                </div>
                {impact ? (
                  <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                    <dt className="text-gray-400">Number</dt><dd className="text-gray-700">{impact.je_number || 'Preview'}</dd>
                    <dt className="text-gray-400">Date</dt><dd className="text-gray-700">{impact.posting_date || 'Not posted'}</dd>
                    <dt className="text-gray-400">Period</dt><dd className="text-gray-700">{impact.fiscal_period_name || 'Not posted'}</dd>
                  </dl>
                ) : <p className="mt-3 text-xs text-gray-400">No posted journal entry.</p>}
              </div>
              <div className="hidden md:flex items-center text-gray-300"><span>→</span></div>
              <div className="px-4 py-4 border-t md:border-t-0 md:border-l border-gray-100">
                <div className="flex items-center gap-2 text-xs font-semibold text-gray-900">
                  <Scale className="h-4 w-4 text-gray-500" aria-hidden="true" />
                  General ledger
                </div>
                {impact ? (
                  <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                    <dt className="text-gray-400">Lines</dt><dd className="text-gray-700">{impact.lines.length}</dd>
                    <dt className="text-gray-400">Debit</dt><dd className="text-gray-700 font-mono">{fmt(Number(impact.total_debit))}</dd>
                    <dt className="text-gray-400">Credit</dt><dd className="text-gray-700 font-mono">{fmt(Number(impact.total_credit))}</dd>
                  </dl>
                ) : <p className="mt-3 text-xs text-gray-400">No GL lines.</p>}
              </div>
            </div>
          </section>

          {impact && (
            <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100">
                <div className="flex items-center justify-between gap-4">
                  <div>
                    <h2 className="text-sm font-semibold text-gray-900">GL Impact</h2>
                    <p className="text-xs text-gray-500 mt-0.5">{impact.rule_explanation}</p>
                  </div>
                  <span className={`text-xs font-medium ${impact.balanced ? 'text-green-700' : 'text-red-600'}`}>
                    {impact.balanced ? 'Balanced' : 'Unbalanced'}
                  </span>
                </div>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-xs">
                  <thead className="bg-gray-50 border-b border-gray-200">
                    <tr>
                      {['Line', 'Account', 'Account Source', 'Description', 'Debit', 'Credit'].map(header => (
                        <th key={header} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Debit', 'Credit'].includes(header) ? 'text-right' : 'text-left'}`}>{header}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {impact.lines.map(line => (
                      <tr key={`${line.line_number}-${line.account_id}`}>
                        <td className="px-3 py-2 text-gray-400">{line.line_number}</td>
                        <td className="px-3 py-2">
                          <Link
                            to={`/account-detail-ledger?accountId=${line.account_id}${trace.journal_entry_id ? `&jeId=${trace.journal_entry_id}` : ''}`}
                            className="font-medium text-blue-700 hover:text-blue-900"
                          >
                            {line.account_code} - {line.account_name}
                          </Link>
                        </td>
                        <td className="px-3 py-2 text-gray-500 font-mono text-[11px]">{line.account_source}</td>
                        <td className="px-3 py-2 text-gray-500">{line.description || '-'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{Number(line.debit) ? fmt(Number(line.debit)) : '-'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{Number(line.credit) ? fmt(Number(line.credit)) : '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot className="bg-gray-50 border-t border-gray-200">
                    <tr>
                      <td colSpan={4} className="px-3 py-2 text-right font-semibold text-gray-700">Totals</td>
                      <td className="px-3 py-2 text-right font-mono font-bold text-gray-900">{fmt(Number(impact.total_debit))}</td>
                      <td className="px-3 py-2 text-right font-mono font-bold text-gray-900">{fmt(Number(impact.total_credit))}</td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            </section>
          )}

          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 flex items-center gap-2">
              <CalendarDays className="h-4 w-4 text-gray-500" aria-hidden="true" />
              <h2 className="text-sm font-semibold text-gray-900">Audit Events</h2>
              <span className="text-xs text-gray-400">{trace.audit_events.length}</span>
            </div>
            {trace.audit_events.length === 0 ? (
              <div className="px-4 py-6 text-sm text-gray-400">No source audit events were found.</div>
            ) : (
              <div className="divide-y divide-gray-100">
                {trace.audit_events.map(event => (
                  <div key={event.id} className="px-4 py-3 grid grid-cols-[minmax(0,1fr)_auto] gap-3 text-xs">
                    <div>
                      <span className="font-medium text-gray-800">{event.action}</span>
                      <span className="text-gray-400 ml-2 font-mono">{event.changed_by?.slice(0, 8) || 'system'}</span>
                    </div>
                    <time className="text-gray-500 whitespace-nowrap">{formatDateTime(event.changed_at)}</time>
                  </div>
                ))}
              </div>
            )}
          </section>
        </>
      ) : null}
    </div>
  )
}
