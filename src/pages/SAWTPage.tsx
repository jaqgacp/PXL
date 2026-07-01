import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  invoice_id: string
  payment_amount: number
  cwt_amount: number
  sales_invoices: { customer_name_snapshot: string; customer_tin_snapshot: string | null } | null
}
type Agg = { customer_key: string; customer_name: string; customer_tin: string; payments: number; cwt: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }

export default function SAWTPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<Agg[]>([])

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const months = QUARTERS[quarter]
    const startDate = `${year}-${String(months[0]).padStart(2, '0')}-01`
    const endDate = new Date(year, months[2], 0).toISOString().split('T')[0]

    const { data } = await supabase.from('receipt_lines')
      .select('invoice_id,payment_amount,cwt_amount,receipts!inner(receipt_date,company_id,status),sales_invoices!inner(customer_name_snapshot,customer_tin_snapshot)')
      .eq('receipts.company_id', companyId).eq('receipts.status', 'posted')
      .gte('receipts.receipt_date', startDate).lte('receipts.receipt_date', endDate)
      .gt('cwt_amount', 0)

    const byCustomer: Record<string, Agg> = {}
    for (const r of (data || []) as unknown as Row[]) {
      const tin = r.sales_invoices?.customer_tin_snapshot || 'unknown'
      if (!byCustomer[tin]) byCustomer[tin] = { customer_key: tin, customer_name: r.sales_invoices?.customer_name_snapshot || 'Unknown', customer_tin: r.sales_invoices?.customer_tin_snapshot || '', payments: 0, cwt: 0 }
      byCustomer[tin].payments += Number(r.payment_amount)
      byCustomer[tin].cwt += Number(r.cwt_amount)
    }
    setRows(Object.values(byCustomer).sort((a, b) => a.customer_name.localeCompare(b.customer_name)))
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalPayments = rows.reduce((s, r) => s + r.payments, 0)
  const totalCwt = rows.reduce((s, r) => s + r.cwt, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
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
        <button onClick={exportCSV} disabled={rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
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
                  <td className="px-4 py-2.5 text-gray-700">{r.customer_name}</td>
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
