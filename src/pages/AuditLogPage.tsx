import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type AuditLog = {
  id: string; company_id: string | null; table_name: string; record_id: string | null
  action: string; old_data: Record<string, unknown> | null; new_data: Record<string, unknown> | null
  changed_by: string | null; changed_at: string; ip_address: string | null
}

const ACTION_COLORS: Record<string, string> = {
  INSERT: 'bg-green-50 text-green-700',
  UPDATE: 'bg-blue-50 text-blue-700',
  DELETE: 'bg-red-50 text-red-700',
}

const TABLE_LABELS: Record<string, string> = {
  companies: 'Company Setup',
  branches: 'Branch Setup',
  departments: 'Departments',
  cost_centers: 'Cost Centers',
  fiscal_years: 'Fiscal Years',
  fiscal_periods: 'Fiscal Periods',
  chart_of_accounts: 'Chart of Accounts',
  exchange_rates: 'Exchange Rates',
  sys_feature_enablement: 'Feature Enablement',
  number_series: 'Number Series',
  approval_workflows: 'Approval Workflows',
  approval_workflow_steps: 'Workflow Steps',
}

export default function AuditLogPage() {
  const [logs, setLogs] = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(false)
  const [filterTable, setFilterTable] = useState('')
  const [filterAction, setFilterAction] = useState('')
  const [search, setSearch] = useState('')
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [page, setPage] = useState(0)
  const PAGE_SIZE = 50

  const fetchLogs = async () => {
    setLoading(true)
    let query = supabase.from('sys_audit_logs')
      .select('*')
      .order('changed_at', { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1)
    if (filterTable) query = query.eq('table_name', filterTable)
    if (filterAction) query = query.eq('action', filterAction)
    const { data } = await query
    setLogs((data as AuditLog[]) || [])
    setLoading(false)
  }

  useEffect(() => { fetchLogs() }, [filterTable, filterAction, page])

  const filteredLogs = search
    ? logs.filter(l => l.table_name.includes(search.toLowerCase()) || (l.changed_by || '').toLowerCase().includes(search.toLowerCase()) || (l.record_id || '').includes(search))
    : logs

  const knownTables = Object.keys(TABLE_LABELS)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">System Audit Log</h1>
          <p className="text-sm text-gray-500 mt-0.5">Immutable log of all data changes across the system</p>
        </div>
        <button onClick={() => { setPage(0); fetchLogs() }}
          className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
          Refresh
        </button>
      </div>

      <div className="bg-amber-50 border border-amber-200 rounded-lg px-4 py-2.5 text-xs text-amber-800">
        Audit logs are append-only and cannot be modified or deleted. They record all INSERT, UPDATE, and DELETE operations.
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search table or user..." />
        <select value={filterTable} onChange={e => { setFilterTable(e.target.value); setPage(0) }}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Tables</option>
          {knownTables.map(t => <option key={t} value={t}>{TABLE_LABELS[t] || t}</option>)}
        </select>
        <select value={filterAction} onChange={e => { setFilterAction(e.target.value); setPage(0) }}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Actions</option>
          <option value="INSERT">INSERT</option>
          <option value="UPDATE">UPDATE</option>
          <option value="DELETE">DELETE</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="text-center py-16 text-sm text-gray-400">Loading audit logs...</div>
        ) : filteredLogs.length === 0 ? (
          <div className="text-center py-16">
            <p className="text-base font-medium text-gray-500">No Audit Logs Found</p>
            <p className="text-sm mt-1 text-gray-400">Audit entries are created automatically when data is changed.</p>
          </div>
        ) : (
          <>
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-200">
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Timestamp</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Action</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Table</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Record ID</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Changed By</th>
                  <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Details</th>
                </tr>
              </thead>
              <tbody>
                {filteredLogs.map((log, i) => (
                  <>
                    <tr key={log.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                      <td className="px-4 py-3 text-gray-600 text-xs font-mono whitespace-nowrap">
                        {new Date(log.changed_at).toLocaleString('en-PH')}
                      </td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${ACTION_COLORS[log.action] || 'bg-gray-100 text-gray-600'}`}>
                          {log.action}
                        </span>
                      </td>
                      <td className="px-4 py-3 font-medium text-gray-800">
                        {TABLE_LABELS[log.table_name] || log.table_name}
                      </td>
                      <td className="px-4 py-3 text-gray-500 font-mono text-xs">
                        {log.record_id ? log.record_id.slice(0, 8) + '...' : '—'}
                      </td>
                      <td className="px-4 py-3 text-gray-600 text-xs">
                        {log.changed_by || 'System'}
                      </td>
                      <td className="px-4 py-3">
                        {(log.old_data || log.new_data) && (
                          <button onClick={() => setExpandedId(expandedId === log.id ? null : log.id)}
                            className="text-xs text-blue-600 hover:text-blue-800 font-medium">
                            {expandedId === log.id ? 'Hide' : 'Show diff'}
                          </button>
                        )}
                      </td>
                    </tr>
                    {expandedId === log.id && (
                      <tr key={log.id + '-detail'} className="bg-blue-50 border-b border-blue-100">
                        <td colSpan={6} className="px-4 py-3">
                          <div className="grid grid-cols-2 gap-4">
                            {log.old_data && (
                              <div>
                                <p className="text-xs font-semibold text-red-600 mb-1">Before</p>
                                <pre className="text-xs text-gray-700 bg-white border border-red-100 rounded p-2 overflow-x-auto max-h-48">{JSON.stringify(log.old_data, null, 2)}</pre>
                              </div>
                            )}
                            {log.new_data && (
                              <div>
                                <p className="text-xs font-semibold text-green-600 mb-1">After</p>
                                <pre className="text-xs text-gray-700 bg-white border border-green-100 rounded p-2 overflow-x-auto max-h-48">{JSON.stringify(log.new_data, null, 2)}</pre>
                              </div>
                            )}
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                ))}
              </tbody>
            </table>
            <div className="px-4 py-3 border-t border-gray-100 flex items-center justify-between text-xs text-gray-500">
              <span>Showing {page * PAGE_SIZE + 1}–{page * PAGE_SIZE + filteredLogs.length} records</span>
              <div className="flex items-center gap-2">
                <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0}
                  className="px-2 py-1 border border-gray-300 rounded disabled:opacity-40 hover:bg-gray-50">← Prev</button>
                <span className="px-2">Page {page + 1}</span>
                <button onClick={() => setPage(p => p + 1)} disabled={filteredLogs.length < PAGE_SIZE}
                  className="px-2 py-1 border border-gray-300 rounded disabled:opacity-40 hover:bg-gray-50">Next →</button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
