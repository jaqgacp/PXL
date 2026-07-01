import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { id: string; period_year: number; period_quarter: number; gross_interest_income: number; fwt_rate: number; fwt_withheld: number; status: string; bank_accounts: { bank_name: string } | null }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function FWTSummaryReportPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('form_2306_issuances').select('id,period_year,period_quarter,gross_interest_income,fwt_rate,fwt_withheld,status,bank_accounts(bank_name)')
      .eq('company_id', companyId).eq('period_year', year).order('period_quarter')
    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId, year])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalGross = rows.reduce((s, r) => s + r.gross_interest_income, 0)
  const totalFwt = rows.reduce((s, r) => s + r.fwt_withheld, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">FWT Summary Report</h1><p className="text-sm text-gray-500 mt-0.5">Final Withholding Tax on bank interest income, by quarter</p></div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross Interest</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">FWT Withheld</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No FWT certificates in this year.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">Q{r.period_quarter} {r.period_year}</td>
                  <td className="px-4 py-2 text-gray-700">{r.bank_accounts?.bank_name || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.gross_interest_income)}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{r.fwt_rate}%</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.fwt_withheld)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalGross)}</td><td /><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalFwt)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
