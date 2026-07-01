import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  company_id: string
  taxable_month: string
  bill_date: string
  supplier_tin: string | null
  registered_name: string | null
  address: string | null
  gross_purchases: number
  exempt_purchases: number
  zero_rated: number
  taxable_base: number
  input_vat: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function SLPPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [selMonth, setSelMonth] = useState(now.getMonth())
  const [selYear, setSelYear] = useState(now.getFullYear())
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<Row[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const taxableMonth = `${String(selMonth + 1).padStart(2, '0')}/${selYear}`
    const { data } = await supabase.from('vw_slp_export').select('*').eq('company_id', companyId).eq('taxable_month', taxableMonth).order('registered_name')
    setRows((data as Row[]) || [])
    setLoading(false)
  }, [companyId, selMonth, selYear])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalGross = rows.reduce((s, r) => s + r.gross_purchases, 0)
  const totalTaxable = rows.reduce((s, r) => s + r.taxable_base, 0)
  const totalVat = rows.reduce((s, r) => s + r.input_vat, 0)
  const yearRange = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    const header = ['Taxable Month', 'Supplier TIN', 'Registered Name', 'Address', 'Gross Purchases', 'Exempt', 'Zero-Rated', 'Taxable Base', 'Input VAT']
    const csvRows = rows.map(r => [r.taxable_month, r.supplier_tin || '', r.registered_name || '', r.address || '', r.gross_purchases.toFixed(2), r.exempt_purchases.toFixed(2), r.zero_rated.toFixed(2), r.taxable_base.toFixed(2), r.input_vat.toFixed(2)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `slp-${MONTHS[selMonth]}-${selYear}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">SLP — Summary List of Purchases</h1>
          <p className="text-sm text-gray-500 mt-0.5">Per-supplier purchase summary for VAT return attachment</p>
        </div>
        <button onClick={exportCSV} disabled={rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={selMonth} onChange={e => setSelMonth(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}</select>
        <select value={selYear} onChange={e => setSelYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{yearRange.map(y => <option key={y} value={y}>{y}</option>)}</select>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Address</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Input VAT</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No purchases recorded for this month.'}</td></tr>
              ) : rows.map((r, i) => (
                <tr key={i} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.registered_name || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-500 max-w-xs truncate">{r.address || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.gross_purchases)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxable_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.input_vat)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} supplier{rows.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalGross)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalTaxable)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalVat)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
