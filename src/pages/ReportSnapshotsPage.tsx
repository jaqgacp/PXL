import { useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type SnapshotRow = {
  id: string; report_type: string; source_table: string; source_id: string
  snapshot_status: string; snapshot_version: number
  period_start: string; period_end: string
  source_hash: string; source_row_count: number
  generated_by: string | null; generated_at: string
}
type SnapshotDetail = SnapshotRow & {
  report_payload: Record<string, unknown>
  source_payload: Record<string, unknown>
}

const LIST_COLUMNS = 'id,report_type,source_table,source_id,snapshot_status,snapshot_version,period_start,period_end,source_hash,source_row_count,generated_by,generated_at'

const REPORT_LABELS: Record<string, string> = {
  '2550M': 'VAT Return 2550M',
  '2550Q': 'VAT Return 2550Q',
  FORM_2307_ISSUED: 'Form 2307 Issued',
  SLSP: 'SLSP Export',
  RELIEF: 'RELIEF Export',
  SAWT: 'SAWT Export',
  QAP: 'QAP Export',
  CAS_SLSP: 'CAS DAT: SLSP',
  CAS_RELIEF: 'CAS DAT: RELIEF',
  CAS_GL: 'CAS DAT: General Ledger',
  CAS_QAP: 'CAS DAT: Alphalist (QAP)',
  BOOKS_SALES_JOURNAL: 'Books: Sales Journal',
  BOOKS_PURCHASE_JOURNAL: 'Books: Purchase Journal',
  BOOKS_CASH_RECEIPTS: 'Books: Cash Receipts',
  BOOKS_CASH_DISBURSEMENTS: 'Books: Cash Disbursements',
  BOOKS_GENERAL_JOURNAL: 'Books: General Journal',
  BOOKS_CASH_SALES_JOURNAL: 'Books: Cash Sales Journal',
  BOOKS_CASH_PURCHASES_JOURNAL: 'Books: Cash Purchases Journal',
}

const STATUS_COLORS: Record<string, string> = {
  final: 'locked', filed: 'posted', sent: 'pending',
  acknowledged: 'approved', exported: 'active', superseded: 'inactive',
}
const STATUSES = ['final', 'filed', 'sent', 'acknowledged', 'exported', 'superseded']

const reportLabel = (t: string) => REPORT_LABELS[t] || t
const fmtDate = (d: string) => new Date(d + 'T00:00:00').toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
const fmtPeriod = (r: SnapshotRow) => `${fmtDate(r.period_start)} – ${fmtDate(r.period_end)}`
const humanize = (k: string) => k.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
const UNGROUPED_KEY = /year|month|quarter|version/i
const fmtVal = (v: unknown, key?: string): string => {
  if (v === null || v === undefined || v === '') return '—'
  if (typeof v === 'number' && key && UNGROUPED_KEY.test(key)) return String(v)
  if (typeof v === 'number') return Number.isInteger(v) ? v.toLocaleString('en-PH') : v.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  if (typeof v === 'boolean') return v ? 'Yes' : 'No'
  if (typeof v === 'object') return JSON.stringify(v)
  return String(v)
}
const isRowArray = (v: unknown): v is Record<string, unknown>[] =>
  Array.isArray(v) && (v.length === 0 || (typeof v[0] === 'object' && v[0] !== null && !Array.isArray(v[0])))

const MAX_SECTION_ROWS = 200

function KVGrid({ obj }: { obj: Record<string, unknown> }) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-3 gap-x-6 gap-y-1 px-4 py-3">
      {Object.entries(obj).map(([k, v]) => (
        <div key={k} className="flex justify-between gap-3 text-sm border-b border-gray-50 py-1">
          <span className="text-gray-500">{humanize(k)}</span>
          <span className={`text-gray-800 text-right ${typeof v === 'number' ? 'font-mono tabular-nums' : ''}`}>{fmtVal(v, k)}</span>
        </div>
      ))}
    </div>
  )
}

function RowsTable({ rows }: { rows: Record<string, unknown>[] }) {
  if (rows.length === 0) return <div className="px-4 py-3 text-sm text-gray-400">No rows.</div>
  const cols = Array.from(rows.slice(0, 50).reduce((s, r) => { Object.keys(r).forEach(k => s.add(k)); return s }, new Set<string>()))
  const numeric = cols.map(c => rows.some(r => typeof r[c] === 'number'))
  const shown = rows.slice(0, MAX_SECTION_ROWS)
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 border-b border-gray-200">
            {cols.map((c, i) => (
              <th key={c} className={`${numeric[i] ? 'text-right' : 'text-left'} px-3 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap`}>{humanize(c)}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {shown.map((r, ri) => (
            <tr key={ri} className="border-b border-gray-100">
              {cols.map((c, i) => (
                <td key={c} className={`px-3 py-1.5 whitespace-nowrap ${numeric[i] ? 'text-right font-mono tabular-nums text-gray-700' : 'text-gray-600'}`}>{fmtVal(r[c], c)}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length > MAX_SECTION_ROWS && (
        <div className="px-4 py-2 text-xs text-gray-400 border-t border-gray-100">Showing first {MAX_SECTION_ROWS} of {rows.length} frozen rows.</div>
      )}
    </div>
  )
}

function PayloadSections({ payload }: { payload: Record<string, unknown> }) {
  const entries = Object.entries(payload)
  const scalars = entries.filter(([, v]) => typeof v !== 'object' || v === null)
  const sections = entries.filter(([, v]) => typeof v === 'object' && v !== null)
  return (
    <div className="space-y-3">
      {scalars.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="bg-gray-50 border-b border-gray-200 px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Values</div>
          <KVGrid obj={Object.fromEntries(scalars)} />
        </div>
      )}
      {sections.map(([k, v]) => (
        <div key={k} className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="bg-gray-50 border-b border-gray-200 px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
            {humanize(k)}{isRowArray(v) ? ` (${(v as unknown[]).length})` : ''}
          </div>
          {isRowArray(v) ? <RowsTable rows={v} /> : <KVGrid obj={v as Record<string, unknown>} />}
        </div>
      ))}
    </div>
  )
}

export default function ReportSnapshotsPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<SnapshotRow[]>([])
  const [loading, setLoading] = useState(false)
  const [filterType, setFilterType] = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [detail, setDetail] = useState<SnapshotDetail | null>(null)
  const [versions, setVersions] = useState<SnapshotRow[]>([])
  const [detailLoading, setDetailLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let query = supabase.from('report_snapshots').select(LIST_COLUMNS)
      .eq('company_id', companyId).order('generated_at', { ascending: false }).limit(200)
    if (filterType) query = query.eq('report_type', filterType)
    if (filterStatus) query = query.eq('snapshot_status', filterStatus)
    if (dateFrom) query = query.gte('period_end', dateFrom)
    if (dateTo) query = query.lte('period_start', dateTo)
    const { data } = await query
    setRows((data as SnapshotRow[] | null) || [])
    setLoading(false)
  }, [companyId, filterType, filterStatus, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const openSnapshot = useCallback(async (id: string) => {
    setDetailLoading(true)
    const { data } = await supabase.from('report_snapshots').select('*').eq('id', id).single()
    const snap = data as SnapshotDetail | null
    setDetail(snap)
    if (snap) {
      const { data: hist } = await supabase.from('report_snapshots').select(LIST_COLUMNS)
        .eq('source_table', snap.source_table).eq('source_id', snap.source_id)
        .order('generated_at', { ascending: false })
      setVersions((hist as SnapshotRow[] | null) || [])
    } else {
      setVersions([])
    }
    setDetailLoading(false)
  }, [])

  const hasFilter = filterType || filterStatus || dateFrom || dateTo

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Report Snapshots</h1>
        <p className="text-sm text-gray-500 mt-0.5">Immutable evidence of filed returns, issued certificates &amp; compliance exports — frozen source rows, hashes &amp; reconciliation at generation time</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={filterType} onChange={e => { setFilterType(e.target.value); setDetail(null) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="">All Reports</option>
          {Object.entries(REPORT_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value); setDetail(null) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="">All Statuses</option>
          {STATUSES.map(s => <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>)}
        </select>
        <label className="text-sm text-gray-500">Period</label>
        <input type="date" value={dateFrom} onChange={e => { setDateFrom(e.target.value); setDetail(null) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-gray-400 text-sm">to</span>
        <input type="date" value={dateTo} onChange={e => { setDateTo(e.target.value); setDetail(null) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        {hasFilter && (
          <button onClick={() => { setFilterType(''); setFilterStatus(''); setDateFrom(''); setDateTo(''); setDetail(null) }} className="text-sm text-gray-500 hover:text-gray-700">× Clear</button>
        )}
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-200">
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Generated</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Report</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Ver</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rows</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Source Hash</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.length === 0 ? (
                  <tr><td colSpan={8} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : hasFilter ? 'No snapshots match the current filters.' : 'No snapshots recorded yet. Snapshots are created when returns are finalized/filed, certificates are sent, or compliance exports run.'}</td></tr>
                ) : rows.map(r => (
                  <tr key={r.id} onClick={() => openSnapshot(r.id)} className={`border-b border-gray-100 hover:bg-gray-50 cursor-pointer ${detail?.id === r.id ? 'bg-blue-50/50' : ''}`}>
                    <td className="px-4 py-2 text-xs text-gray-500 whitespace-nowrap">{new Date(r.generated_at).toLocaleString('en-PH')}</td>
                    <td className="px-4 py-2 text-gray-700 whitespace-nowrap">{reportLabel(r.report_type)}</td>
                    <td className="px-4 py-2"><StatusBadge status={STATUS_COLORS[r.snapshot_status] || 'draft'} label={r.snapshot_status} /></td>
                    <td className="px-4 py-2 text-right text-gray-700">{r.snapshot_version}</td>
                    <td className="px-4 py-2 text-gray-600 whitespace-nowrap">{fmtPeriod(r)}</td>
                    <td className="px-4 py-2 text-right text-gray-700">{r.source_row_count.toLocaleString('en-PH')}</td>
                    <td className="px-4 py-2 font-mono text-xs text-gray-500">{r.source_hash.slice(0, 16)}…</td>
                    <td className="px-4 py-2" onClick={event => event.stopPropagation()}>
                      <ReportTraceLink
                        companyId={companyId}
                        reportFamily="report_snapshot"
                        filters={{ record_id: r.id }}
                        className="text-xs font-medium text-blue-600 hover:text-blue-800 whitespace-nowrap"
                        title="Open the accounting sources frozen in this snapshot"
                      >
                        Trace
                      </ReportTraceLink>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {detailLoading && <div className="bg-white border border-gray-200 rounded-lg p-8 text-center text-sm text-gray-400">Loading snapshot…</div>}

      {!detailLoading && detail && (
        <div className="space-y-3">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="bg-gray-50 border-b border-gray-200 px-4 py-2.5 flex items-center justify-between gap-3 flex-wrap">
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold text-gray-800">{reportLabel(detail.report_type)}</span>
                <StatusBadge status={STATUS_COLORS[detail.snapshot_status] || 'draft'} label={detail.snapshot_status} />
                <span className="text-xs text-gray-500">v{detail.snapshot_version}</span>
              </div>
              <div className="flex items-center gap-3">
                <ReportTraceLink
                  companyId={companyId}
                  reportFamily="report_snapshot"
                  filters={{ record_id: detail.id }}
                  className="text-xs font-medium text-blue-600 hover:text-blue-800"
                  title="Open the accounting sources frozen in this snapshot"
                >
                  Trace accounting
                </ReportTraceLink>
                <button onClick={() => setDetail(null)} className="text-sm text-gray-400 hover:text-gray-600">× Close</button>
              </div>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-2 px-4 py-3 text-sm">
              <div><div className="text-xs text-gray-400 uppercase tracking-wide">Period</div><div className="text-gray-800">{fmtPeriod(detail)}</div></div>
              <div><div className="text-xs text-gray-400 uppercase tracking-wide">Generated At</div><div className="text-gray-800">{new Date(detail.generated_at).toLocaleString('en-PH')}</div></div>
              <div><div className="text-xs text-gray-400 uppercase tracking-wide">Source</div><div className="text-gray-800 font-mono text-xs">{detail.source_table}<br />{detail.source_id}</div></div>
              <div><div className="text-xs text-gray-400 uppercase tracking-wide">Frozen Rows</div><div className="text-gray-800">{detail.source_row_count.toLocaleString('en-PH')}</div></div>
              <div className="col-span-2 md:col-span-4"><div className="text-xs text-gray-400 uppercase tracking-wide">SHA-256 Source Hash</div><div className="text-gray-800 font-mono text-xs break-all">{detail.source_hash}</div></div>
            </div>
          </div>

          {versions.length > 1 && (
            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="bg-gray-50 border-b border-gray-200 px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Snapshot History for This Source ({versions.length})</div>
              <table className="w-full text-sm">
                <tbody>
                  {versions.map(v => (
                    <tr key={v.id} onClick={() => openSnapshot(v.id)} className={`border-b border-gray-100 hover:bg-gray-50 cursor-pointer ${v.id === detail.id ? 'bg-blue-50/50' : ''}`}>
                      <td className="px-4 py-1.5 text-xs text-gray-500 whitespace-nowrap">{new Date(v.generated_at).toLocaleString('en-PH')}</td>
                      <td className="px-4 py-1.5"><StatusBadge status={STATUS_COLORS[v.snapshot_status] || 'draft'} label={v.snapshot_status} /></td>
                      <td className="px-4 py-1.5 text-gray-600">v{v.snapshot_version}</td>
                      <td className="px-4 py-1.5 text-right text-gray-600">{v.source_row_count.toLocaleString('en-PH')} rows</td>
                      <td className="px-4 py-1.5 font-mono text-xs text-gray-500">{v.source_hash.slice(0, 16)}…</td>
                      <td className="px-4 py-1.5" onClick={event => event.stopPropagation()}>
                        <ReportTraceLink
                          companyId={companyId}
                          reportFamily="report_snapshot"
                          filters={{ record_id: v.id }}
                          className="text-xs font-medium text-blue-600 hover:text-blue-800"
                          title="Open the accounting sources frozen in this snapshot"
                        >
                          Trace
                        </ReportTraceLink>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div>
            <div className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Report Payload (Frozen)</div>
            <PayloadSections payload={detail.report_payload} />
          </div>

          <div>
            <div className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Source Payload (Hashed Evidence)</div>
            <PayloadSections payload={detail.source_payload} />
          </div>
        </div>
      )}
    </div>
  )
}
