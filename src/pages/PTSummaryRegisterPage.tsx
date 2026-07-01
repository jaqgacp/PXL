import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type ReturnRow = {
  id: string
  period_year: number
  period_quarter: number
  gross_sales_exempt: number
  gross_sales_zero_rated: number
  taxable_base: number
  pt_rate: number
  pt_due: number
  pt_paid_prior_quarters: number
  pt_still_due: number
  status: string
  filed_date: string | null
  reference_no: string | null
}

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`

export default function PTSummaryRegisterPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [yearFrom, setYearFrom] = useState(now.getFullYear() - 1)
  const [yearTo, setYearTo] = useState(now.getFullYear())
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<ReturnRow[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('pt_returns').select('*')
      .eq('company_id', companyId).gte('period_year', yearFrom).lte('period_year', yearTo)
      .order('period_year').order('period_quarter')
    setRows((data as ReturnRow[]) || [])
    setLoading(false)
  }, [companyId, yearFrom, yearTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalDue = rows.reduce((s, r) => s + r.pt_due, 0)
  const totalStillDue = rows.reduce((s, r) => s + r.pt_still_due, 0)
  const years = Array.from({ length: 8 }, (_, i) => now.getFullYear() - 6 + i)

  const exportCSV = () => {
    const header = ['Quarter', 'Exempt Sales', 'Zero-Rated Sales', 'Taxable Base', 'PT Rate', 'PT Due', 'Paid Prior', 'Still Due', 'Status', 'Filed Date', 'Reference No.']
    const csvRows = rows.map(r => [
      fmtQuarter(r.period_year, r.period_quarter), r.gross_sales_exempt.toFixed(2), r.gross_sales_zero_rated.toFixed(2),
      r.taxable_base.toFixed(2), r.pt_rate.toFixed(2), r.pt_due.toFixed(2), r.pt_paid_prior_quarters.toFixed(2),
      r.pt_still_due.toFixed(2), r.status, r.filed_date || '', r.reference_no || '',
    ])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `pt-summary-register-${yearFrom}-${yearTo}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">PT Summary Register</h1>
          <p className="text-sm text-gray-500 mt-0.5">All Percentage Tax quarterly returns, {yearFrom}–{yearTo}</p>
        </div>
        <button onClick={exportCSV} disabled={rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={yearFrom} onChange={e => setYearFrom(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        <span className="text-xs text-gray-400">to</span>
        <select value={yearTo} onChange={e => setYearTo(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Returns Filed</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{rows.length}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Total PT Due</p>
          <p className="text-2xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(totalDue)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Total Still Due</p>
          <p className="text-2xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(totalStillDue)}</p>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">PT Due</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Still Due</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Filed Date</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400">
                  {!companyId ? 'Select a company from the context bar above.' : 'No PT returns in this period.'}
                </td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.taxable_base)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{r.pt_rate}%</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.pt_due)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.pt_still_due)}</td>
                  <td className="px-4 py-3 text-xs text-gray-600">{r.status[0].toUpperCase() + r.status.slice(1)}</td>
                  <td className="px-4 py-3 text-xs text-gray-400">{r.filed_date || '—'}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} return{rows.length !== 1 ? 's' : ''}</td>
                  <td colSpan={2} />
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmtNum(totalDue)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmtNum(totalStillDue)}</td>
                  <td colSpan={2} />
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
