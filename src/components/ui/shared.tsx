import { useEffect, useState } from 'react'

// ── StatusBadge ──────────────────────────────────────────────
const STATUS_STYLES: Record<string, string> = {
  active: 'bg-green-50 text-green-700',
  inactive: 'bg-gray-100 text-gray-500',
  draft: 'bg-gray-100 text-gray-600',
  pending: 'bg-yellow-50 text-yellow-700',
  approved: 'bg-green-50 text-green-700',
  posted: 'bg-blue-50 text-blue-700',
  error: 'bg-red-50 text-red-700',
  success: 'bg-green-50 text-green-700',
  locked: 'bg-orange-50 text-orange-700',
  open: 'bg-blue-50 text-blue-700',
  closed: 'bg-gray-100 text-gray-500',
  head_office: 'bg-purple-50 text-purple-700',
  branch: 'bg-blue-50 text-blue-700',
}

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const cls = STATUS_STYLES[status] || 'bg-gray-100 text-gray-600'
  const text = label || (status.charAt(0).toUpperCase() + status.slice(1).replace(/_/g, ' '))
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls}`}>
      {text}
    </span>
  )
}

// ── AmountCell ────────────────────────────────────────────────
export function AmountCell({ amount }: { amount: number | null | undefined }) {
  if (amount === null || amount === undefined) return <span className="text-gray-400">—</span>
  return (
    <span className="font-mono tabular-nums">
      {new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(amount)}
    </span>
  )
}

// ── DateCell ──────────────────────────────────────────────────
export function DateCell({ date }: { date: string | null | undefined }) {
  if (!date) return <span className="text-gray-400">—</span>
  try {
    return <span>{new Date(date + 'T00:00:00').toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })}</span>
  } catch {
    return <span className="text-gray-400">—</span>
  }
}

// ── EmptyState ────────────────────────────────────────────────
export function EmptyState({ title, description, action }: {
  title: string; description?: string; action?: React.ReactNode
}) {
  return (
    <div className="text-center py-16">
      <p className="text-base font-medium text-gray-500">{title}</p>
      {description && <p className="text-sm mt-1 text-gray-400">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}

// ── FormSection ───────────────────────────────────────────────
export function FormSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6 space-y-4">
      <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100">
        {title}
      </h2>
      {children}
    </div>
  )
}

// ── ConfirmDialog ─────────────────────────────────────────────
export function ConfirmDialog({ open, onClose, onConfirm, title, message, confirmLabel = 'Confirm', danger = false }: {
  open: boolean; onClose: () => void; onConfirm: () => void;
  title: string; message: string; confirmLabel?: string; danger?: boolean
}) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
        <h2 className="text-base font-semibold text-gray-900 mb-2">{title}</h2>
        <p className="text-sm text-gray-600 mb-6">{message}</p>
        <div className="flex justify-end gap-2">
          <button onClick={onClose}
            className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
            Cancel
          </button>
          <button onClick={onConfirm}
            className={`px-4 py-2 rounded-md text-sm font-medium text-white ${danger ? 'bg-red-600 hover:bg-red-700' : 'bg-gray-900 hover:bg-gray-800'}`}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

// ── DataTable ─────────────────────────────────────────────────
export type Column<T> = {
  key: string
  label: string
  render?: (row: T) => React.ReactNode
  className?: string
}

export function DataTable<T extends Record<string, unknown>>({
  columns, data, keyField = 'id', loading, emptyTitle = 'No records found',
  emptyDescription, onRowClick,
}: {
  columns: Column<T>[]; data: T[]; keyField?: string; loading?: boolean;
  emptyTitle?: string; emptyDescription?: string; onRowClick?: (row: T) => void
}) {
  if (loading) {
    return (
      <div className="text-center py-16 text-sm text-gray-400">Loading...</div>
    )
  }
  if (data.length === 0) {
    return <EmptyState title={emptyTitle} description={emptyDescription} />
  }
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="bg-gray-50 border-b border-gray-200">
          {columns.map(col => (
            <th key={col.key}
              className={`text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide ${col.className || ''}`}>
              {col.label}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {data.map((row, i) => (
          <tr key={String(row[keyField]) || i}
            onClick={() => onRowClick?.(row)}
            className={`border-b border-gray-100 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''} ${onRowClick ? 'hover:bg-gray-50 cursor-pointer' : 'hover:bg-gray-50'}`}>
            {columns.map(col => (
              <td key={col.key} className={`px-4 py-3 ${col.className || ''}`}>
                {col.render ? col.render(row) : String(row[col.key] ?? '—')}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )
}

// ── LookupDialog ──────────────────────────────────────────────
export function LookupDialog({ open, onClose, onSelect, title, columns, data, searchKeys = [] }: {
  open: boolean; onClose: () => void; onSelect: (item: Record<string, unknown>) => void;
  title: string; columns: { key: string; label: string }[];
  data: Record<string, unknown>[]; searchKeys?: string[]
}) {
  const [q, setQ] = useState('')
  if (!open) return null
  const filtered = q.trim()
    ? data.filter(row => searchKeys.some(k => String(row[k] ?? '').toLowerCase().includes(q.toLowerCase())))
    : data
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-2xl z-10 flex flex-col max-h-[80vh]">
        <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-gray-900">{title}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-700 text-lg leading-none">×</button>
        </div>
        <div className="px-4 py-2 border-b border-gray-100">
          <input value={q} onChange={e => setQ(e.target.value)} autoFocus
            className="w-full border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
            placeholder="Search..." />
        </div>
        <div className="overflow-y-auto flex-1">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-gray-50 border-b border-gray-200">
              <tr>
                {columns.map(c => (
                  <th key={c.key} className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase">{c.label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0
                ? <tr><td colSpan={columns.length} className="text-center py-8 text-gray-400 text-sm">No results</td></tr>
                : filtered.map((row, i) => (
                  <tr key={i} onClick={() => { onSelect(row); onClose() }}
                    className="border-b border-gray-100 hover:bg-blue-50 cursor-pointer">
                    {columns.map(c => (
                      <td key={c.key} className="px-4 py-2">{String(row[c.key] ?? '—')}</td>
                    ))}
                  </tr>
                ))
              }
            </tbody>
          </table>
        </div>
        <div className="px-4 py-2 border-t border-gray-100 text-xs text-gray-400">
          {filtered.length} result{filtered.length !== 1 ? 's' : ''}
        </div>
      </div>
    </div>
  )
}

// ── AuditTrailSection ─────────────────────────────────────────
export function AuditTrailSection({ tableName, recordId, initiallyExpanded = false }: { tableName: string; recordId: string; initiallyExpanded?: boolean }) {
  const [logs, setLogs] = useState<Array<{
    id: string; action: string; changed_by: string | null; changed_at: string
    ip_address: string | null; user_agent: string | null; old_data: unknown; new_data: unknown
  }>>([])
  const [expanded, setExpanded] = useState(initiallyExpanded)
  const [loaded, setLoaded] = useState(false)

  const load = async () => {
    const { supabase } = await import('@/lib/supabase')
    const { data } = await supabase
      .from('sys_audit_logs')
      .select('id,action,changed_by,changed_at,ip_address,user_agent,old_data,new_data')
      .eq('table_name', tableName)
      .eq('record_id', recordId)
      .order('changed_at', { ascending: true })
      .limit(50)
    setLogs((data || []).map(l => ({ ...l, changed_at: l.changed_at ?? '' })))
    setLoaded(true)
    setExpanded(true)
  }

  useEffect(() => {
    if (initiallyExpanded && !loaded) void load()
    // Load once for the selected record; explicit refresh is handled by remounting the tab.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initiallyExpanded, recordId, tableName])

  const changedFields = (oldData: unknown, newData: unknown) => {
    if (!oldData || !newData || typeof oldData !== 'object' || typeof newData !== 'object') return '—'
    const oldRow = oldData as Record<string, unknown>
    const newRow = newData as Record<string, unknown>
    const keys = Object.keys(newRow).filter(key => JSON.stringify(oldRow[key]) !== JSON.stringify(newRow[key]))
    return keys.length > 0 ? keys.join(', ') : '—'
  }

  return (
    <div className="bg-white border border-gray-200 rounded overflow-hidden">
      <button
        onClick={expanded ? () => setExpanded(false) : (loaded ? () => setExpanded(true) : load)}
        className="w-full flex items-center justify-between px-3 py-2 text-[10px] font-semibold text-gray-500 uppercase tracking-wide hover:bg-gray-50">
        Audit Trail
        <span className="text-gray-400">{expanded ? '▲' : '▼'}</span>
      </button>
      {expanded && (
        <div className="border-t border-gray-100 overflow-x-auto">
          {logs.length === 0
            ? <p className="px-3 py-4 text-center text-xs text-gray-400">No audit history available.</p>
            : (
              <table className="w-full text-xs">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-200">
                    <th className="text-left px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500">Timestamp</th>
                    <th className="text-left px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500">Event</th>
                    <th className="text-left px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500">User</th>
                    <th className="text-left px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500">IP</th>
                    <th className="text-left px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500">Device</th>
                    <th className="text-left px-2 py-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-500">Changes</th>
                  </tr>
                </thead>
                <tbody>
                  {logs.map(log => (
                    <tr key={log.id} className="border-b border-gray-100">
                      <td className="px-2 py-1.5 text-gray-500 whitespace-nowrap">
                        {new Date(log.changed_at).toLocaleString('en-PH')}
                      </td>
                      <td className="px-2 py-1.5">
                        <span className={`px-1.5 py-0.5 rounded text-xs font-medium ${
                          log.action === 'INSERT' ? 'bg-green-50 text-green-700' :
                          log.action === 'UPDATE' ? 'bg-blue-50 text-blue-700' :
                          'bg-red-50 text-red-700'}`}>
                          {log.action}
                        </span>
                      </td>
                      <td className="px-2 py-1.5 text-gray-600 font-mono">{log.changed_by || '—'}</td>
                      <td className="px-2 py-1.5 text-gray-500 font-mono">{log.ip_address || '—'}</td>
                      <td className="px-2 py-1.5 text-gray-500 max-w-48 truncate" title={log.user_agent || ''}>{log.user_agent || '—'}</td>
                      <td className="px-2 py-1.5 text-gray-500 max-w-64 truncate" title={changedFields(log.old_data, log.new_data)}>{changedFields(log.old_data, log.new_data)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
        </div>
      )}
    </div>
  )
}

export type AuditEvidenceFact = {
  label: string
  value: React.ReactNode
}

export function AuditEvidenceBlock({
  tableName,
  recordId,
  facts,
  title = 'Audit Evidence',
  initiallyExpanded = false,
}: {
  tableName: string
  recordId: string | null | undefined
  facts: AuditEvidenceFact[]
  title?: string
  initiallyExpanded?: boolean
}) {
  if (!recordId) return null

  return (
    <div className="px-5 py-4 bg-gray-50 border-t border-gray-100 space-y-3">
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-3">{title}</div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
          {facts.map(fact => (
            <div key={fact.label}>
              <div className="text-[10px] uppercase tracking-wide text-gray-400 mb-1">{fact.label}</div>
              <div className="text-xs font-medium text-gray-700">{fact.value}</div>
            </div>
          ))}
        </div>
      </div>
      <AuditTrailSection tableName={tableName} recordId={recordId} initiallyExpanded={initiallyExpanded} />
    </div>
  )
}
