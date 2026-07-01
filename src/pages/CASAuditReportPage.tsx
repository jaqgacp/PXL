import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }

type ActionCounts = { INSERT: number; UPDATE: number; DELETE: number }

export default function CASAuditReportPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [loading, setLoading] = useState(false)
  const [totalChanges, setTotalChanges] = useState(0)
  const [byTable, setByTable] = useState<{ table: string; count: number }[]>([])
  const [byAction, setByAction] = useState<ActionCounts>({ INSERT: 0, UPDATE: 0, DELETE: 0 })
  const [voidCount, setVoidCount] = useState(0)
  const [voidAmount, setVoidAmount] = useState(0)
  const [atpAlerts, setAtpAlerts] = useState(0)
  const [datFilesGenerated, setDatFilesGenerated] = useState(0)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: auditData }, { data: siVoid }, { data: vbVoid }, { data: pvVoid }, { data: atpSeries }, { count: datCount }] = await Promise.all([
      supabase.from('sys_audit_logs').select('table_name,action').eq('company_id', companyId).gte('changed_at', dateFrom).lte('changed_at', dateTo + 'T23:59:59').limit(5000),
      supabase.from('sales_invoices').select('total_amount').eq('company_id', companyId).eq('status', 'cancelled').gte('date', dateFrom).lte('date', dateTo),
      supabase.from('vendor_bills').select('total_amount').eq('company_id', companyId).eq('status', 'cancelled').gte('bill_date', dateFrom).lte('bill_date', dateTo),
      supabase.from('payment_vouchers').select('total_amount').eq('company_id', companyId).eq('status', 'cancelled').gte('voucher_date', dateFrom).lte('voucher_date', dateTo),
      supabase.from('number_series').select('next_number,atp_series_end,atp_alert_threshold').eq('company_id', companyId).not('atp_series_start', 'is', null),
      supabase.from('cas_export_log').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('export_type', 'dat_file').gte('generated_at', dateFrom).lte('generated_at', dateTo + 'T23:59:59'),
    ])

    const rows = (auditData || []) as { table_name: string; action: string }[]
    setTotalChanges(rows.length)

    const tableCounts: Record<string, number> = {}
    const actionCounts: ActionCounts = { INSERT: 0, UPDATE: 0, DELETE: 0 }
    for (const r of rows) {
      tableCounts[r.table_name] = (tableCounts[r.table_name] || 0) + 1
      if (r.action in actionCounts) actionCounts[r.action as keyof ActionCounts] += 1
    }
    setByTable(Object.entries(tableCounts).map(([table, count]) => ({ table, count })).sort((a, b) => b.count - a.count).slice(0, 10))
    setByAction(actionCounts)

    const voids = [...(siVoid || []), ...(vbVoid || []), ...(pvVoid || [])] as { total_amount: number }[]
    setVoidCount(voids.length)
    setVoidAmount(voids.reduce((s, v) => s + Number(v.total_amount), 0))

    const alerts = ((atpSeries || []) as { next_number: number; atp_series_end: number; atp_alert_threshold: number | null }[])
      .filter(s => s.atp_alert_threshold != null && (s.atp_series_end - s.next_number + 1) <= s.atp_alert_threshold).length
    setAtpAlerts(alerts)
    setDatFilesGenerated(datCount || 0)

    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">CAS Audit Report</h1>
          <p className="text-sm text-gray-500 mt-0.5">System audit trail completeness summary for BIR CAS examination</p>
        </div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <>
          <div className="grid grid-cols-5 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Total Changes</p><p className="text-xl font-bold text-gray-900 mt-1">{totalChanges}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Voided Documents</p><p className="text-xl font-bold text-gray-900 mt-1">{voidCount}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Void Amount</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(voidAmount)}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">ATP Alerts</p><p className={`text-xl font-bold mt-1 ${atpAlerts > 0 ? 'text-red-600' : 'text-gray-900'}`}>{atpAlerts}</p></div>
            <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">DAT Files Generated</p><p className="text-xl font-bold text-gray-900 mt-1">{datFilesGenerated}</p></div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Changes by Action</h2></div>
              <div className="p-4 space-y-2">
                <div className="flex justify-between text-sm"><span className="text-gray-600">Insert</span><span className="font-mono font-semibold text-gray-900">{byAction.INSERT}</span></div>
                <div className="flex justify-between text-sm"><span className="text-gray-600">Update</span><span className="font-mono font-semibold text-gray-900">{byAction.UPDATE}</span></div>
                <div className="flex justify-between text-sm"><span className="text-gray-600">Delete</span><span className="font-mono font-semibold text-gray-900">{byAction.DELETE}</span></div>
              </div>
            </div>

            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Top Changed Tables</h2></div>
              <div className="p-4 space-y-2">
                {byTable.length === 0 ? <p className="text-sm text-gray-400">No changes in this period.</p> : byTable.map(t => (
                  <div key={t.table} className="flex justify-between text-sm"><span className="text-gray-600">{t.table}</span><span className="font-mono font-semibold text-gray-900">{t.count}</span></div>
                ))}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
