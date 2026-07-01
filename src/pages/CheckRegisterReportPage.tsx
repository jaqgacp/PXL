import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  voucher_date: string
  cv_number: string
  check_number: string
  check_date: string
  payee: string
  net_check_amount: number
  status: string
  bank_accounts: { bank_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }
const STATUS_CLS: Record<string, string> = { draft: 'bg-gray-100 text-gray-600', posted: 'bg-blue-50 text-blue-700', released: 'bg-amber-50 text-amber-700', cleared: 'bg-green-50 text-green-700', stale: 'bg-red-50 text-red-700', cancelled: 'bg-gray-100 text-gray-400' }

export default function CheckRegisterReportPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('check_vouchers')
      .select('id,voucher_date,cv_number,check_number,check_date,payee,net_check_amount,status,bank_accounts(bank_name)')
      .eq('company_id', companyId).gte('voucher_date', dateFrom).lte('voucher_date', dateTo).order('voucher_date', { ascending: false })
    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const total = rows.reduce((s, r) => s + r.net_check_amount, 0)

  const exportCSV = () => {
    const header = ['Date', 'CV No.', 'Check No.', 'Check Date', 'Payee', 'Bank', 'Amount', 'Status']
    const csvRows = rows.map(r => [r.voucher_date, r.cv_number, r.check_number, r.check_date, r.payee, r.bank_accounts?.bank_name || '', r.net_check_amount.toFixed(2), r.status])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `check-register-${dateFrom}-to-${dateTo}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Check Register</h1><p className="text-sm text-gray-500 mt-0.5">All check vouchers issued in the period</p></div>
        <button onClick={exportCSV} disabled={rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">CV No.</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Check No.</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Payee</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No check vouchers in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.voucher_date}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono">{r.cv_number}</td>
                  <td className="px-4 py-2 text-gray-500 font-mono">{r.check_number}</td>
                  <td className="px-4 py-2 text-gray-700">{r.payee}</td>
                  <td className="px-4 py-2 text-gray-500">{r.bank_accounts?.bank_name || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.net_check_amount)}</td>
                  <td className="px-4 py-2"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium capitalize ${STATUS_CLS[r.status] || 'bg-gray-100 text-gray-600'}`}>{r.status}</span></td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} check{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(total)}</td><td /></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
