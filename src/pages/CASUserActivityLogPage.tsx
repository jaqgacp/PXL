import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type LogRow = { id: string; table_name: string; action: string; changed_by: string | null; changed_at: string }
type UserAgg = { user_id: string; count: number; lastActivity: string; tables: Set<string> }

const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }

export default function CASUserActivityLogPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [users, setUsers] = useState<UserAgg[]>([])
  const [selectedUser, setSelectedUser] = useState<string | null>(null)
  const [userLogs, setUserLogs] = useState<LogRow[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('sys_audit_logs').select('id,table_name,action,changed_by,changed_at')
      .eq('company_id', companyId).gte('changed_at', dateFrom).lte('changed_at', dateTo + 'T23:59:59')
      .order('changed_at', { ascending: false }).limit(2000)

    const byUser: Record<string, UserAgg> = {}
    for (const r of (data || []) as LogRow[]) {
      const uid = r.changed_by || 'system'
      if (!byUser[uid]) byUser[uid] = { user_id: uid, count: 0, lastActivity: r.changed_at, tables: new Set() }
      byUser[uid].count += 1
      byUser[uid].tables.add(r.table_name)
      if (r.changed_at > byUser[uid].lastActivity) byUser[uid].lastActivity = r.changed_at
    }
    setUsers(Object.values(byUser).sort((a, b) => b.count - a.count))
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const viewUser = async (userId: string) => {
    if (!companyId) return
    setSelectedUser(userId)
    const query = supabase.from('sys_audit_logs').select('id,table_name,action,changed_by,changed_at')
      .eq('company_id', companyId).gte('changed_at', dateFrom).lte('changed_at', dateTo + 'T23:59:59')
      .order('changed_at', { ascending: false }).limit(200)
    const { data } = userId === 'system' ? await query.is('changed_by', null) : await query.eq('changed_by', userId)
    setUserLogs((data as LogRow[]) || [])
  }

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">User Activity Log</h1>
        <p className="text-sm text-gray-500 mt-0.5">Per-user change activity across the system</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={e => { setDateFrom(e.target.value); setSelectedUser(null) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={dateTo} onChange={e => { setDateTo(e.target.value); setSelectedUser(null) }} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Users</h2></div>
          {loading ? (
            <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
          ) : (
            <table className="w-full text-sm">
              <thead><tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">User</th>
                <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Changes</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Last Activity</th>
              </tr></thead>
              <tbody>
                {users.length === 0 ? (
                  <tr><td colSpan={3} className="text-center py-12 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No activity in this period.'}</td></tr>
                ) : users.map(u => (
                  <tr key={u.user_id} onClick={() => viewUser(u.user_id)} className={`border-b border-gray-100 hover:bg-gray-50 cursor-pointer ${selectedUser === u.user_id ? 'bg-blue-50/50' : ''}`}>
                    <td className="px-4 py-2 font-mono text-xs text-gray-700">{u.user_id === 'system' ? 'System' : u.user_id.slice(0, 8)}</td>
                    <td className="px-4 py-2 text-right text-gray-700">{u.count}</td>
                    <td className="px-4 py-2 text-xs text-gray-500">{new Date(u.lastActivity).toLocaleString('en-PH')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Activity Detail</h2></div>
          {!selectedUser ? (
            <div className="p-8 text-center text-sm text-gray-400">Select a user to view their activity.</div>
          ) : (
            <table className="w-full text-sm">
              <thead><tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date/Time</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Table</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Action</th>
              </tr></thead>
              <tbody>
                {userLogs.map(l => (
                  <tr key={l.id} className="border-b border-gray-100">
                    <td className="px-4 py-2 text-xs text-gray-600">{new Date(l.changed_at).toLocaleString('en-PH')}</td>
                    <td className="px-4 py-2 text-gray-700">{l.table_name}</td>
                    <td className="px-4 py-2 text-xs text-gray-500">{l.action}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  )
}
