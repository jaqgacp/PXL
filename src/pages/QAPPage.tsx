import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { supplier_id: string; supplier_name: string | null; supplier_tin: string | null; atc_code: string | null; tax_base: number; tax_withheld: number }
type Agg = { supplier_id: string; supplier_name: string; supplier_tin: string; atc_codes: Set<string>; tax_base: number; tax_withheld: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }

export default function QAPPage() {
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

    const { data } = await supabase.from('vw_ewt_summary_ap').select('supplier_id,supplier_name,supplier_tin,atc_code,tax_base,tax_withheld')
      .eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)

    const bySupplier: Record<string, Agg> = {}
    for (const r of (data || []) as Row[]) {
      const key = r.supplier_id
      if (!bySupplier[key]) bySupplier[key] = { supplier_id: key, supplier_name: r.supplier_name || 'Unknown', supplier_tin: r.supplier_tin || '', atc_codes: new Set(), tax_base: 0, tax_withheld: 0 }
      bySupplier[key].tax_base += Number(r.tax_base)
      bySupplier[key].tax_withheld += Number(r.tax_withheld)
      if (r.atc_code) bySupplier[key].atc_codes.add(r.atc_code)
    }
    setRows(Object.values(bySupplier).sort((a, b) => a.supplier_name.localeCompare(b.supplier_name)))
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalBase = rows.reduce((s, r) => s + r.tax_base, 0)
  const totalWithheld = rows.reduce((s, r) => s + r.tax_withheld, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    const header = ['TIN', 'Registered Name', 'ATC Codes', 'Income Payments', 'Tax Withheld']
    const csvRows = rows.map(r => [r.supplier_tin, r.supplier_name, Array.from(r.atc_codes).join('; '), r.tax_base.toFixed(2), r.tax_withheld.toFixed(2)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `qap-Q${quarter}-${year}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">QAP — Quarterly Alphalist of Payees</h1>
          <p className="text-sm text-gray-500 mt-0.5">Per-supplier EWT summary — attachment to 1601EQ filing</p>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATC Codes</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Income Payments</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Withheld</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No EWT payees in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.supplier_id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_name}</td>
                  <td className="px-4 py-2.5 text-gray-500">{Array.from(r.atc_codes).join(', ') || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.tax_withheld)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} payee{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBase)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalWithheld)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
