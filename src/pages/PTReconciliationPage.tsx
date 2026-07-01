import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type ReturnRow = { period_year: number; period_quarter: number; taxable_base: number; pt_due: number; status: string }

type ReconRow = {
  period_year: number
  period_quarter: number
  books_taxable_base: number
  books_pt_due: number
  filed_taxable_base: number
  filed_pt_due: number
  variance: number
  status: string
}

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`
const quarterMonths = (q: number) => [(q - 1) * 3 + 1, (q - 1) * 3 + 2, (q - 1) * 3 + 3]

export default function PTReconciliationPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<ReconRow[]>([])
  const [ptRate, setPtRate] = useState(3)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const { data: profile } = await supabase.from('compliance_profiles').select('percentage_tax_rate').eq('company_id', companyId).maybeSingle()
    const rate = profile?.percentage_tax_rate ? Number(profile.percentage_tax_rate) : 3
    setPtRate(rate)

    const { data: filedData } = await supabase.from('pt_returns').select('period_year,period_quarter,taxable_base,pt_due,status').eq('company_id', companyId).eq('period_year', year)
    const filedMap = new Map<number, ReturnRow>()
    for (const r of (filedData || []) as ReturnRow[]) filedMap.set(r.period_quarter, r)

    const results: ReconRow[] = []
    for (const q of [1, 2, 3, 4]) {
      const months = quarterMonths(q)
      const startDate = `${year}-${String(months[0]).padStart(2, '0')}-01`
      const endDate = new Date(year, months[2], 0).toISOString().split('T')[0]

      const { data } = await supabase
        .from('sales_invoice_lines')
        .select(`net_amount, vat_codes!inner(vat_classification), sales_invoices!inner(date, status, company_id)`)
        .eq('sales_invoices.company_id', companyId)
        .eq('sales_invoices.status', 'posted')
        .gte('sales_invoices.date', startDate)
        .lte('sales_invoices.date', endDate)
        .in('vat_codes.vat_classification', ['exempt', 'zero_rated'])

      const booksBase = ((data || []) as Record<string, unknown>[]).reduce((s, r) => s + Number(r.net_amount), 0)
      const booksDue = booksBase * (rate / 100)

      const filed = filedMap.get(q)
      const filedBase = filed ? Number(filed.taxable_base) : 0
      const filedDue = filed ? Number(filed.pt_due) : 0

      results.push({
        period_year: year, period_quarter: q,
        books_taxable_base: booksBase, books_pt_due: booksDue,
        filed_taxable_base: filedBase, filed_pt_due: filedDue,
        variance: booksDue - filedDue,
        status: filed ? filed.status : 'not_filed',
      })
    }
    setRows(results)
    setLoading(false)
  }, [companyId, year])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">PT Reconciliation</h1>
        <p className="text-sm text-gray-500 mt-0.5">Books (posted sales) vs. Filed Percentage Tax Returns — PT rate {ptRate}%</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          {years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Books — Taxable Base</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Books — PT Due</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Filed — Taxable Base</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Filed — PT Due</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Variance</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Filing Status</th>
              </tr>
            </thead>
            <tbody>
              {!companyId ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400">Select a company from the context bar above.</td></tr>
              ) : rows.map(r => (
                <tr key={r.period_quarter} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.books_taxable_base)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.books_pt_due)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.filed_taxable_base)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.filed_pt_due)}</td>
                  <td className={`px-4 py-3 text-right font-mono tabular-nums font-semibold ${Math.abs(r.variance) < 0.01 ? 'text-gray-400' : 'text-red-600'}`}>{fmtNum(r.variance)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                      r.status === 'not_filed' ? 'bg-amber-50 text-amber-700' : r.status === 'filed' ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-600'
                    }`}>
                      {r.status === 'not_filed' ? 'Not Filed' : r.status[0].toUpperCase() + r.status.slice(1)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
