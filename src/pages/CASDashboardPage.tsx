import { useState, useEffect, useCallback, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

const LINKS = [
  { label: 'Transaction Audit Log', page: 'cas-transaction-audit-log' },
  { label: 'Master Data Change Log', page: 'cas-master-data-change-log' },
  { label: 'System Parameter Logs', page: 'cas-system-parameter-logs' },
  { label: 'User Activity Log', page: 'cas-user-activity-log' },
  { label: 'Attachment Register', page: 'cas-attachment-register' },
  { label: 'Document Void Register', page: 'cas-document-void-register' },
  { label: 'ATP Usage Log', page: 'cas-atp-usage-log' },
  { label: 'DAT File Generation', page: 'cas-dat-file-generation' },
  { label: 'CAS Audit Report', page: 'cas-audit-report' },
  { label: 'Export History', page: 'cas-export-history' },
]

export default function CASDashboardPage() {
  const { companyId } = useAppCtx()
  const navigate = useNavigate()
  const now = useMemo(() => new Date(), [])
  const [changesThisMonth, setChangesThisMonth] = useState(0)
  const [atpAlerts, setAtpAlerts] = useState(0)
  const [attachmentCount, setAttachmentCount] = useState(0)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`

    const [{ count: changeCount }, { data: atpSeries }, { count: attCount }] = await Promise.all([
      supabase.from('sys_audit_logs').select('id', { count: 'exact', head: true }).eq('company_id', companyId).gte('changed_at', startDate),
      supabase.from('number_series').select('next_number,atp_series_end,atp_alert_threshold').eq('company_id', companyId).not('atp_series_start', 'is', null),
      supabase.from('cas_attachment_register').select('id', { count: 'exact', head: true }).eq('company_id', companyId),
    ])

    setChangesThisMonth(changeCount || 0)
    setAtpAlerts(((atpSeries || []) as { next_number: number; atp_series_end: number; atp_alert_threshold: number | null }[])
      .filter(s => s.atp_alert_threshold != null && (s.atp_series_end - s.next_number + 1) <= s.atp_alert_threshold).length)
    setAttachmentCount(attCount || 0)
    setLoading(false)
  }, [companyId, now])

  useEffect(() => { load() }, [load])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">CAS Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">Computerized Accounting System — audit trail &amp; compliance overview</p>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">System Changes — This Month</p>
              <p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : changesThisMonth}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">ATP Alerts</p>
              <p className={`text-xl font-bold mt-1 ${atpAlerts > 0 ? 'text-red-600' : 'text-gray-900'}`}>{loading ? '—' : atpAlerts}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Attachments Logged</p>
              <p className="text-xl font-bold text-gray-900 mt-1">{loading ? '—' : attachmentCount}</p>
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Audit &amp; CAS Pages</h2></div>
            <div className="divide-y divide-gray-100">
              {LINKS.map(item => (
                <button key={item.page} onClick={() => navigate(`/${item.page}`)} className="w-full flex items-center justify-between px-4 py-3 text-sm hover:bg-gray-50 transition-colors text-left">
                  <span className="text-gray-900 font-medium">{item.label}</span>
                  <span className="text-gray-400">→</span>
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
