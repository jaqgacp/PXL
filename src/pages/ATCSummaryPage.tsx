import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { atc_code: string | null; nature_of_payment: string | null; tax_rate: number | null; tax_base: number; tax_withheld: number }
type Agg = { atc_code: string; nature_of_payment: string; tax_rate: number | null; tax_base: number; tax_withheld: number; count: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }

export default function ATCSummaryPage() {
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

    const { data } = await supabase.from('vw_ewt_summary_ap').select('atc_code,nature_of_payment,tax_rate,tax_base,tax_withheld')
      .eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)

    const byAtc: Record<string, Agg> = {}
    for (const r of (data || []) as Row[]) {
      const key = r.atc_code || 'UNSPECIFIED'
      if (!byAtc[key]) byAtc[key] = { atc_code: key, nature_of_payment: r.nature_of_payment || '', tax_rate: r.tax_rate, tax_base: 0, tax_withheld: 0, count: 0 }
      byAtc[key].tax_base += Number(r.tax_base)
      byAtc[key].tax_withheld += Number(r.tax_withheld)
      byAtc[key].count += 1
    }
    setRows(Object.values(byAtc).sort((a, b) => b.tax_withheld - a.tax_withheld))
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalBase = rows.reduce((s, r) => s + r.tax_base, 0)
  const totalWithheld = rows.reduce((s, r) => s + r.tax_withheld, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    const header = ['ATC Code', 'Nature of Payment', 'Rate', 'Tax Base', 'Tax Withheld', 'Transactions']
    const csvRows = rows.map(r => [r.atc_code, r.nature_of_payment, r.tax_rate ?? '', r.tax_base.toFixed(2), r.tax_withheld.toFixed(2), r.count])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `atc-summary-Q${quarter}-${year}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">ATC Summary</h1>
          <p className="text-sm text-gray-500 mt-0.5">EWT payable breakdown by Alphanumeric Tax Code</p>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATC Code</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Nature of Payment</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Withheld</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Transactions</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No EWT transactions in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.atc_code} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 font-medium text-gray-900">{r.atc_code}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.nature_of_payment || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{r.tax_rate != null ? `${r.tax_rate}%` : '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.tax_withheld)}</td>
                  <td className="px-4 py-2.5 text-right text-gray-500">{r.count}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBase)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalWithheld)}</td><td /></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
