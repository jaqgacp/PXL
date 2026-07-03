import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type SalesRow = { transaction_id: string; invoice_date: string; system_no: string | null; customer_tin: string | null; customer_name: string | null; gross_sales: number; taxable_base: number; output_vat: number }
type PurchRow = { transaction_id: string; invoice_date: string; system_no: string | null; supplier_tin: string | null; supplier_name: string | null; gross_purchases: number; taxable_base: number; input_vat: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function RELIEFExportPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [selMonth, setSelMonth] = useState(now.getMonth())
  const [selYear, setSelYear] = useState(now.getFullYear())
  const [tab, setTab] = useState<'sales' | 'purchases'>('sales')
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [sales, setSales] = useState<SalesRow[]>([])
  const [purchases, setPurchases] = useState<PurchRow[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-01`
    const endDay = new Date(selYear, selMonth + 1, 0).getDate()
    const endDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-${endDay}`

    const [{ data: outData }, { data: inData }] = await Promise.all([
      supabase.from('vw_output_vat_review').select('transaction_id,invoice_date,system_no,customer_tin,customer_name,gross_sales,taxable_base,output_vat')
        .eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate).order('invoice_date'),
      supabase.from('vw_input_vat_review').select('transaction_id,invoice_date,system_no,supplier_tin,supplier_name,gross_purchases,taxable_base,input_vat')
        .eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate).order('invoice_date'),
    ])

    setSales((outData as SalesRow[]) || [])
    setPurchases((inData as PurchRow[]) || [])
    setLoading(false)
  }, [companyId, selMonth, selYear])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalSalesVat = sales.reduce((s, r) => s + r.output_vat, 0)
  const totalPurchVat = purchases.reduce((s, r) => s + r.input_vat, 0)
  const yearRange = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const downloadCSV = (rows: (string | number)[][], filename: string) => {
    const csv = rows.map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = filename; a.click()
    URL.revokeObjectURL(url)
  }

  const exportCSV = async () => {
    if (!companyId) return
    setExporting(true)
    const { error } = await supabase.rpc('fn_snapshot_vat_export', {
      p_company_id: companyId,
      p_report_type: 'RELIEF',
      p_year: selYear,
      p_month: selMonth + 1,
      p_export_part: tab,
    })
    setExporting(false)
    if (error) {
      alert(error.message)
      return
    }

    if (tab === 'sales') {
      const header = ['Date', 'Doc No.', 'Customer TIN', 'Customer Name', 'Gross Amount', 'Taxable Base', 'Output VAT']
      downloadCSV([header, ...sales.map(r => [r.invoice_date, r.system_no || '', r.customer_tin || '', r.customer_name || '', r.gross_sales.toFixed(2), r.taxable_base.toFixed(2), r.output_vat.toFixed(2)])], `relief-sales-${MONTHS[selMonth]}-${selYear}.csv`)
    } else {
      const header = ['Date', 'Doc No.', 'Supplier TIN', 'Supplier Name', 'Gross Amount', 'Taxable Base', 'Input VAT']
      downloadCSV([header, ...purchases.map(r => [r.invoice_date, r.system_no || '', r.supplier_tin || '', r.supplier_name || '', r.gross_purchases.toFixed(2), r.taxable_base.toFixed(2), r.input_vat.toFixed(2)])], `relief-purchases-${MONTHS[selMonth]}-${selYear}.csv`)
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">RELIEF Export</h1>
          <p className="text-sm text-gray-500 mt-0.5">Reconciliation of Listings for Enforcement — per-transaction detail</p>
        </div>
        <button onClick={exportCSV} disabled={exporting || (tab === 'sales' ? sales : purchases).length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{exporting ? 'Exporting...' : '↓ Export CSV'}</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={selMonth} onChange={e => setSelMonth(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}</select>
        <select value={selYear} onChange={e => setSelYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{yearRange.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <div className="ml-auto flex border border-gray-200 rounded-md overflow-hidden">
          <button onClick={() => setTab('sales')} className={`px-4 py-1.5 text-sm font-medium ${tab === 'sales' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>Sales</button>
          <button onClick={() => setTab('purchases')} className={`px-4 py-1.5 text-sm font-medium ${tab === 'purchases' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>Purchases</button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : tab === 'sales' ? (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Doc No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer Name</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Output VAT</th>
              </tr>
            </thead>
            <tbody>
              {sales.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No sales transactions in this period.'}</td></tr>
              ) : sales.map(r => (
                <tr key={r.transaction_id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.invoice_date}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.system_no || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.customer_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.customer_name || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxable_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.output_vat)}</td>
                </tr>
              ))}
            </tbody>
            {sales.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {sales.length} transaction{sales.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalSalesVat)}</td></tr>
              </tfoot>
            )}
          </table>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Doc No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Supplier TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Supplier Name</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Input VAT</th>
              </tr>
            </thead>
            <tbody>
              {purchases.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No purchase transactions in this period.'}</td></tr>
              ) : purchases.map(r => (
                <tr key={r.transaction_id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.invoice_date}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.system_no || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_name || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxable_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.input_vat)}</td>
                </tr>
              ))}
            </tbody>
            {purchases.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {purchases.length} transaction{purchases.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalPurchVat)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
