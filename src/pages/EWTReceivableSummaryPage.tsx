import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  receipt_id: string
  invoice_id: string
  payment_amount: number
  cwt_amount: number
  receipts: { receipt_date: string; or_number: string } | null
  sales_invoices: { si_number: string; customer_name_snapshot: string; customer_tin_snapshot: string | null } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }

export default function EWTReceivableSummaryPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<Row[]>([])
  const [search, setSearch] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const months = QUARTERS[quarter]
    const startDate = `${year}-${String(months[0]).padStart(2, '0')}-01`
    const endDate = new Date(year, months[2], 0).toISOString().split('T')[0]

    const { data } = await supabase.from('receipt_lines')
      .select('id,receipt_id,invoice_id,payment_amount,cwt_amount,receipts!inner(receipt_date,or_number,company_id,status),sales_invoices!inner(si_number,customer_name_snapshot,customer_tin_snapshot)')
      .eq('receipts.company_id', companyId).eq('receipts.status', 'posted')
      .gte('receipts.receipt_date', startDate).lte('receipts.receipt_date', endDate)
      .gt('cwt_amount', 0)

    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const filtered = rows.filter(r => !search || (r.sales_invoices?.customer_name_snapshot || '').toLowerCase().includes(search.toLowerCase()))
  const totalPayment = filtered.reduce((s, r) => s + r.payment_amount, 0)
  const totalCwt = filtered.reduce((s, r) => s + r.cwt_amount, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    const header = ['OR Date', 'OR Number', 'SI Number', 'Customer', 'TIN', 'Payment Amount', 'CWT Withheld']
    const csvRows = filtered.map(r => [r.receipts?.receipt_date || '', r.receipts?.or_number || '', r.sales_invoices?.si_number || '', r.sales_invoices?.customer_name_snapshot || '', r.sales_invoices?.customer_tin_snapshot || '', r.payment_amount.toFixed(2), r.cwt_amount.toFixed(2)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `ewt-receivable-Q${quarter}-${year}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">EWT Receivable Summary</h1>
          <p className="text-sm text-gray-500 mt-0.5">Creditable Withholding Tax withheld by customers on collections (Form 2307 received)</p>
        </div>
        <button onClick={exportCSV} disabled={filtered.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search customer..." className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56" />
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Collections</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalPayment)}</p></div>
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">CWT Withheld (Receivable)</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalCwt)}</p></div>
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Records</p><p className="text-xl font-bold text-gray-900 mt-1">{filtered.length}</p></div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">OR Date</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">OR Number</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">SI Number</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Payment</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">CWT Withheld</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No CWT-bearing collections in this period.'}</td></tr>
              ) : filtered.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.receipts?.receipt_date}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.receipts?.or_number}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.sales_invoices?.si_number}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.sales_invoices?.customer_name_snapshot}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.payment_amount)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.cwt_amount)}</td>
                </tr>
              ))}
            </tbody>
            {filtered.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {filtered.length} record{filtered.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalPayment)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalCwt)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
