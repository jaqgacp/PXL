import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type SalesRow = { tin: string; name: string; gross: number; exempt: number; zeroRated: number; taxable: number; vat: number }
type PurchaseRow = { supplier_tin: string | null; registered_name: string | null; gross_purchases: number; exempt_purchases: number; zero_rated: number; taxable_base: number; input_vat: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function SLSPExportPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [selMonth, setSelMonth] = useState(now.getMonth())
  const [selYear, setSelYear] = useState(now.getFullYear())
  const [tab, setTab] = useState<'sales' | 'purchases'>('sales')
  const [loading, setLoading] = useState(false)
  const [sales, setSales] = useState<SalesRow[]>([])
  const [purchases, setPurchases] = useState<PurchaseRow[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-01`
    const endDay = new Date(selYear, selMonth + 1, 0).getDate()
    const endDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-${endDay}`
    const taxableMonth = `${String(selMonth + 1).padStart(2, '0')}/${selYear}`

    const [{ data: outData }, { data: slpData }] = await Promise.all([
      supabase.from('vw_output_vat_review').select('*').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      supabase.from('vw_slp_export').select('*').eq('company_id', companyId).eq('taxable_month', taxableMonth).order('registered_name'),
    ])

    const salesMap = new Map<string, SalesRow>()
    for (const r of (outData || []) as { customer_tin: string | null; customer_name: string | null; gross_sales: number; exempt_sales: number; zero_rated_sales: number; taxable_base: number; output_vat: number }[]) {
      const key = r.customer_tin || r.customer_name || 'unknown'
      const existing = salesMap.get(key) || { tin: r.customer_tin || '', name: r.customer_name || 'Unknown', gross: 0, exempt: 0, zeroRated: 0, taxable: 0, vat: 0 }
      existing.gross += r.gross_sales; existing.exempt += r.exempt_sales; existing.zeroRated += r.zero_rated_sales
      existing.taxable += r.taxable_base; existing.vat += r.output_vat
      salesMap.set(key, existing)
    }
    setSales(Array.from(salesMap.values()).sort((a, b) => a.name.localeCompare(b.name)))
    setPurchases((slpData as PurchaseRow[]) || [])
    setLoading(false)
  }, [companyId, selMonth, selYear])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalSalesGross = sales.reduce((s, r) => s + r.gross, 0)
  const totalSalesVat = sales.reduce((s, r) => s + r.vat, 0)
  const totalPurchGross = purchases.reduce((s, r) => s + r.gross_purchases, 0)
  const totalPurchVat = purchases.reduce((s, r) => s + r.input_vat, 0)
  const yearRange = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    if (tab === 'sales') {
      const header = ['Customer TIN', 'Customer Name', 'Gross Sales', 'Exempt', 'Zero-Rated', 'Taxable Base', 'Output VAT']
      const csvRows = sales.map(r => [r.tin, r.name, r.gross.toFixed(2), r.exempt.toFixed(2), r.zeroRated.toFixed(2), r.taxable.toFixed(2), r.vat.toFixed(2)])
      downloadCSV([header, ...csvRows], `sls-${MONTHS[selMonth]}-${selYear}.csv`)
    } else {
      const header = ['Supplier TIN', 'Registered Name', 'Gross Purchases', 'Exempt', 'Zero-Rated', 'Taxable Base', 'Input VAT']
      const csvRows = purchases.map(r => [r.supplier_tin || '', r.registered_name || '', r.gross_purchases.toFixed(2), r.exempt_purchases.toFixed(2), r.zero_rated.toFixed(2), r.taxable_base.toFixed(2), r.input_vat.toFixed(2)])
      downloadCSV([header, ...csvRows], `slp-${MONTHS[selMonth]}-${selYear}.csv`)
    }
  }

  const downloadCSV = (rows: (string | number)[][], filename: string) => {
    const csv = rows.map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = filename; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">SLSP Export</h1>
          <p className="text-sm text-gray-500 mt-0.5">Summary List of Sales and Purchases — combined BIR attachment</p>
        </div>
        <button onClick={exportCSV} disabled={(tab === 'sales' ? sales : purchases).length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export {tab === 'sales' ? 'SLS' : 'SLP'} CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={selMonth} onChange={e => setSelMonth(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}</select>
        <select value={selYear} onChange={e => setSelYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{yearRange.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <div className="ml-auto flex border border-gray-200 rounded-md overflow-hidden">
          <button onClick={() => setTab('sales')} className={`px-4 py-1.5 text-sm font-medium ${tab === 'sales' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>SLS — Sales</button>
          <button onClick={() => setTab('purchases')} className={`px-4 py-1.5 text-sm font-medium ${tab === 'purchases' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>SLP — Purchases</button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : tab === 'sales' ? (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer Name</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross Sales</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Output VAT</th>
              </tr>
            </thead>
            <tbody>
              {sales.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No sales recorded for this month.'}</td></tr>
              ) : sales.map((r, i) => (
                <tr key={i} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.name}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.gross)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxable)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.vat)}</td>
                </tr>
              ))}
            </tbody>
            {sales.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {sales.length} customer{sales.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalSalesGross)}</td>
                  <td />
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalSalesVat)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Supplier TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross Purchases</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Input VAT</th>
              </tr>
            </thead>
            <tbody>
              {purchases.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No purchases recorded for this month.'}</td></tr>
              ) : purchases.map((r, i) => (
                <tr key={i} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.registered_name || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.gross_purchases)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxable_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.input_vat)}</td>
                </tr>
              ))}
            </tbody>
            {purchases.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {purchases.length} supplier{purchases.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalPurchGross)}</td>
                  <td />
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalPurchVat)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
