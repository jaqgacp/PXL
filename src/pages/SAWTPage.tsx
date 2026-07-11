import { useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { customer_id: string | null; customer_tin: string | null; customer_name: string | null; income_payment: number; cwt_withheld: number }
type Agg = { customer_key: string; customer_id: string | null; customer_name: string; customer_tin: string; payments: number; cwt: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }
const quarterDates = (year: number, quarter: number) => {
  const months = QUARTERS[quarter]
  return {
    dateFrom: `${year}-${String(months[0]).padStart(2, '0')}-01`,
    dateTo: new Date(year, months[2], 0).toISOString().split('T')[0],
  }
}

export default function SAWTPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [rows, setRows] = useState<Agg[]>([])
  const { dateFrom, dateTo } = quarterDates(year, quarter)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const { data } = await supabase.from('vw_cwt_summary_ar')
      .select('customer_id,customer_tin,customer_name,income_payment,cwt_withheld')
      .eq('company_id', companyId)
      .gte('receipt_date', dateFrom).lte('receipt_date', dateTo)

    const byCustomer: Record<string, Agg> = {}
    for (const r of (data || []) as unknown as Row[]) {
      const key = r.customer_tin || 'unknown'
      if (!byCustomer[key]) byCustomer[key] = { customer_key: key, customer_id: r.customer_id, customer_name: r.customer_name || 'Unknown', customer_tin: r.customer_tin || '', payments: 0, cwt: 0 }
      else if (byCustomer[key].customer_id !== r.customer_id) byCustomer[key].customer_id = null
      byCustomer[key].payments += Number(r.income_payment)
      byCustomer[key].cwt += Number(r.cwt_withheld)
    }
    setRows(Object.values(byCustomer).sort((a, b) => a.customer_name.localeCompare(b.customer_name)))
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalPayments = rows.reduce((s, r) => s + r.payments, 0)
  const totalCwt = rows.reduce((s, r) => s + r.cwt, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = async () => {
    if (!companyId) return
    setExporting(true)
    const { error } = await supabase.rpc('fn_snapshot_wht_export', {
      p_company_id: companyId,
      p_report_type: 'SAWT',
      p_year: year,
      p_quarter: quarter,
    })
    setExporting(false)
    if (error) {
      alert(error.message)
      return
    }
    const header = ['Customer TIN', 'Customer Name', 'Income Payments', 'CWT Withheld']
    const csvRows = rows.map(r => [r.customer_tin, r.customer_name, r.payments.toFixed(2), r.cwt.toFixed(2)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `sawt-Q${quarter}-${year}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">SAWT — Summary Alphalist of Withholding Tax</h1>
          <p className="text-sm text-gray-500 mt-0.5">Per-customer CWT withheld on collections — attachment to quarterly/annual ITR</p>
        </div>
        <button onClick={exportCSV} disabled={exporting || rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{exporting ? 'Exporting...' : '↓ Export CSV'}</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer Name</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Income Payments</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">CWT Withheld</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={4} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No CWT-bearing collections in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.customer_key} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.customer_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">
                    {r.customer_id ? (
                      <ReportTraceLink
                        companyId={companyId}
                        reportFamily="tax"
                        filters={{ tax_kind: 'cwt_receivable', counterparty_id: r.customer_id, date_from: dateFrom, date_to: dateTo }}
                        title="Open the accounting sources included for this payer"
                      >
                        {r.customer_name}
                      </ReportTraceLink>
                    ) : r.customer_name}
                  </td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.payments)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.cwt)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} payer{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalPayments)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalCwt)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
