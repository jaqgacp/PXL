import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type ReturnRow = { period_month: number; output_vat: number; total_available_input_vat: number; net_vat_payable: number; status: string }

type ReconRow = {
  month: number
  books_output_vat: number
  books_input_vat: number
  books_net: number
  filed_output_vat: number
  filed_input_vat: number
  filed_net: number
  variance: number
  status: string
}

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function VATReconciliationPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<ReconRow[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const { data: filedData } = await supabase.from('vat_returns').select('period_month,output_vat,total_available_input_vat,net_vat_payable,status')
      .eq('company_id', companyId).eq('return_type', '2550M').eq('period_year', year)
    const filedMap = new Map<number, ReturnRow>()
    for (const r of (filedData || []) as ReturnRow[]) filedMap.set(r.period_month, r)

    const results: ReconRow[] = []
    for (let m = 1; m <= 12; m++) {
      const startDate = `${year}-${String(m).padStart(2, '0')}-01`
      const endDate = new Date(year, m, 0).toISOString().split('T')[0]

      const [{ data: outData }, { data: inData }] = await Promise.all([
        supabase.from('vw_output_vat_review').select('output_vat').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
        supabase.from('vw_input_vat_review').select('input_vat').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      ])

      const booksOutput = ((outData || []) as { output_vat: number }[]).reduce((s, r) => s + Number(r.output_vat), 0)
      const booksInput = ((inData || []) as { input_vat: number }[]).reduce((s, r) => s + Number(r.input_vat), 0)
      const filed = filedMap.get(m)

      results.push({
        month: m,
        books_output_vat: booksOutput, books_input_vat: booksInput, books_net: booksOutput - booksInput,
        filed_output_vat: filed ? filed.output_vat : 0, filed_input_vat: filed ? filed.total_available_input_vat : 0, filed_net: filed ? filed.net_vat_payable : 0,
        variance: (booksOutput - booksInput) - (filed ? filed.net_vat_payable : 0),
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
        <h1 className="text-xl font-semibold text-gray-900">VAT Reconciliation</h1>
        <p className="text-sm text-gray-500 mt-0.5">Books (posted transactions) vs. Filed 2550M Returns</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Month</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Books — Net VAT</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Filed — Net VAT</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Variance</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Filing Status</th>
              </tr>
            </thead>
            <tbody>
              {!companyId ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">Select a company from the context bar above.</td></tr>
              ) : rows.map(r => (
                <tr key={r.month} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{MONTHS[r.month - 1]} {year}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.books_net)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.filed_net)}</td>
                  <td className={`px-4 py-3 text-right font-mono tabular-nums font-semibold ${Math.abs(r.variance) < 0.01 ? 'text-gray-400' : 'text-red-600'}`}>{fmtNum(r.variance)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${r.status === 'not_filed' ? 'bg-amber-50 text-amber-700' : r.status === 'filed' ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-600'}`}>
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
