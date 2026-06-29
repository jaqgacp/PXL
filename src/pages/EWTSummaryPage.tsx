import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type EWTRow = {
  transaction_id: string; invoice_date: string
  supplier_tin: string | null; supplier_name: string
  atc_code: string; nature_of_payment: string
  tax_rate: number; tax_base: number; tax_withheld: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const QUARTERS: Record<number, number[]> = { 1: [1,2,3], 2: [4,5,6], 3: [7,8,9], 4: [10,11,12] }

export default function EWTSummaryPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [rows, setRows] = useState<EWTRow[]>([])
  const [loading, setLoading] = useState(false)
  const [supplierSearch, setSupplierSearch] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const months = QUARTERS[quarter]
    const startDate = `${year}-${String(months[0]).padStart(2, '0')}-01`
    const lastMonth = months[months.length - 1]
    const endDate = new Date(year, lastMonth, 0).toISOString().split('T')[0]
    const { data } = await supabase.from('vw_ewt_summary_ap')
      .select('*').eq('company_id', companyId)
      .gte('invoice_date', startDate).lte('invoice_date', endDate)
      .order('invoice_date').order('supplier_name')
    setRows(data as EWTRow[] || [])
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const filtered = supplierSearch
    ? rows.filter(r => r.supplier_name.toLowerCase().includes(supplierSearch.toLowerCase()) || (r.supplier_tin || '').includes(supplierSearch))
    : rows

  // Group by ATC for summary
  const byATC: Record<string, { atc: string; nature: string; rate: number; base: number; withheld: number }> = {}
  filtered.forEach(r => {
    if (!byATC[r.atc_code]) byATC[r.atc_code] = { atc: r.atc_code, nature: r.nature_of_payment, rate: r.tax_rate, base: 0, withheld: 0 }
    byATC[r.atc_code].base += r.tax_base
    byATC[r.atc_code].withheld += r.tax_withheld
  })

  const totalWithheld = filtered.reduce((s, r) => s + r.tax_withheld, 0)
  const totalBase = filtered.reduce((s, r) => s + r.tax_base, 0)

  const exportCSV = () => {
    const headers = ['Invoice Date','Supplier TIN','Supplier Name','ATC Code','Nature of Payment','Tax Rate','Tax Base','Tax Withheld']
    const csvRows = filtered.map(r => [r.invoice_date, r.supplier_tin || '', r.supplier_name, r.atc_code, r.nature_of_payment, r.tax_rate, r.tax_base.toFixed(2), r.tax_withheld.toFixed(2)].join(','))
    const csv = [headers.join(','), ...csvRows].join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }))
    a.download = `EWT_Summary_Q${quarter}_${year}.csv`
    a.click()
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900'

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">EWT Summary</h2>
        <button onClick={exportCSV} className="px-3 py-1.5 text-xs border border-gray-300 rounded-md hover:bg-gray-50">Export QAP CSV</button>
      </div>

      <div className="flex gap-3 flex-wrap">
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Year</label>
          <select value={year} onChange={e => setYear(+e.target.value)} className={inp}>
            {[now.getFullYear() - 1, now.getFullYear()].map(y => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Quarter</label>
          <select value={quarter} onChange={e => setQuarter(+e.target.value)} className={inp}>
            {[1,2,3,4].map(q => <option key={q} value={q}>Q{q}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Supplier</label>
          <input type="text" value={supplierSearch} onChange={e => setSupplierSearch(e.target.value)} placeholder="Filter by name or TIN…" className={inp + ' w-52'} />
        </div>
      </div>

      {/* KPI Strip */}
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-white border border-gray-200 rounded-lg p-3">
          <p className="text-xs text-gray-500">Total Tax Base</p>
          <p className="text-base font-semibold font-mono mt-0.5 text-gray-900">{fmt(totalBase)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-3">
          <p className="text-xs text-gray-500">Total EWT Withheld</p>
          <p className="text-base font-semibold font-mono mt-0.5 text-red-700">{fmt(totalWithheld)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-3">
          <p className="text-xs text-gray-500">ATC Codes Used</p>
          <p className="text-base font-semibold mt-0.5 text-gray-900">{Object.keys(byATC).length}</p>
        </div>
      </div>

      {/* Summary by ATC */}
      {Object.keys(byATC).length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
          <p className="text-xs font-semibold text-blue-700 mb-2 uppercase tracking-wide">Summary by ATC Code</p>
          <div className="grid gap-1">
            {Object.values(byATC).map(g => (
              <div key={g.atc} className="flex items-center gap-2 text-xs">
                <span className="font-mono text-blue-800 w-16">{g.atc}</span>
                <span className="text-gray-600 flex-1">{g.nature}</span>
                <span className="text-gray-500">{g.rate}%</span>
                <span className="font-mono text-gray-700 w-24 text-right">{fmt(g.base)}</span>
                <span className="font-mono text-red-700 w-24 text-right font-medium">{fmt(g.withheld)}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : filtered.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No EWT records for Q{quarter} {year}.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Date','Supplier TIN','Supplier Name','ATC Code','Nature of Payment','Rate','Tax Base','EWT Withheld'].map(h => (
                  <th key={h} className={`px-3 py-2 font-medium text-gray-500 ${['Rate','Tax Base','EWT Withheld'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtered.map((row, i) => (
                <tr key={i} className="hover:bg-gray-50">
                  <td className="px-3 py-1.5 text-gray-500">{row.invoice_date}</td>
                  <td className="px-3 py-1.5 font-mono text-gray-600">{row.supplier_tin || '—'}</td>
                  <td className="px-3 py-1.5 text-gray-700 max-w-[160px] truncate">{row.supplier_name}</td>
                  <td className="px-3 py-1.5 font-mono font-medium text-blue-700">{row.atc_code}</td>
                  <td className="px-3 py-1.5 text-gray-600">{row.nature_of_payment}</td>
                  <td className="px-3 py-1.5 text-right font-mono text-gray-500">{row.tax_rate}%</td>
                  <td className="px-3 py-1.5 text-right font-mono">{fmt(row.tax_base)}</td>
                  <td className="px-3 py-1.5 text-right font-mono font-medium text-red-700">{fmt(row.tax_withheld)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot className="bg-gray-50 border-t-2 border-gray-300 font-semibold text-xs">
              <tr>
                <td colSpan={6} className="px-3 py-2 text-right text-gray-600">Total</td>
                <td className="px-3 py-2 text-right font-mono">{fmt(totalBase)}</td>
                <td className="px-3 py-2 text-right font-mono text-red-700">{fmt(totalWithheld)}</td>
              </tr>
            </tfoot>
          </table>
        )}
      </div>
    </div>
  )
}
