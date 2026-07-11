import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AccountingTraceLink, ReportTraceLink } from '@/components/AccountingTraceLink'

type Row = {
  transaction_id: string
  source_module: string
  source_doc_type: string
  source_doc_id: string
  invoice_date: string
  customer_tin: string | null
  customer_name: string | null
  system_no: string | null
  gross_sales: number
  exempt_sales: number
  zero_rated_sales: number
  taxable_base: number
  output_vat: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function VATOutputSummaryPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [selMonth, setSelMonth] = useState(now.getMonth())
  const [selYear, setSelYear] = useState(now.getFullYear())
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<Row[]>([])
  const [search, setSearch] = useState('')

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-01`
    const endDay = new Date(selYear, selMonth + 1, 0).getDate()
    const endDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-${endDay}`

    const { data } = await supabase.from('vw_output_vat_review')
      .select('transaction_id,source_module,source_doc_type,source_doc_id,invoice_date,customer_tin,customer_name,system_no,gross_sales,exempt_sales,zero_rated_sales,taxable_base,output_vat')
      .eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)
      .order('invoice_date')

    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId, selMonth, selYear])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const filtered = rows.filter(r => !search || (r.customer_name || '').toLowerCase().includes(search.toLowerCase()) || (r.system_no || '').toLowerCase().includes(search.toLowerCase()))

  const totalGross = filtered.reduce((s, r) => s + r.gross_sales, 0)
  const totalExempt = filtered.reduce((s, r) => s + r.exempt_sales, 0)
  const totalZero = filtered.reduce((s, r) => s + r.zero_rated_sales, 0)
  const totalTaxable = filtered.reduce((s, r) => s + r.taxable_base, 0)
  const totalVat = filtered.reduce((s, r) => s + r.output_vat, 0)
  const yearRange = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)
  const periodStart = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-01`
  const periodEnd = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-${new Date(selYear, selMonth + 1, 0).getDate()}`

  const exportCSV = () => {
    const header = ['Date', 'Source', 'System No.', 'Customer', 'TIN', 'Gross Sales', 'Exempt', 'Zero-Rated', 'Taxable Base', 'Output VAT']
    const csvRows = filtered.map(r => [r.invoice_date, r.source_module, r.system_no || '', r.customer_name || '', r.customer_tin || '', r.gross_sales.toFixed(2), r.exempt_sales.toFixed(2), r.zero_rated_sales.toFixed(2), r.taxable_base.toFixed(2), r.output_vat.toFixed(2)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `output-vat-summary-${MONTHS[selMonth]}-${selYear}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Output VAT Summary</h1>
          <p className="text-sm text-gray-500 mt-0.5">Sales, credit &amp; debit memos — output VAT by month</p>
        </div>
        <button onClick={exportCSV} disabled={filtered.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={selMonth} onChange={e => setSelMonth(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}
        </select>
        <select value={selYear} onChange={e => setSelYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {yearRange.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search customer or doc no..." className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56" />
      </div>

      <div className="grid grid-cols-4 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Gross Sales</p>
          <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalGross)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Exempt + Zero-Rated</p>
          <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalExempt + totalZero)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Taxable Base</p>
          <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalTaxable)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Output VAT</p>
          <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">
            <ReportTraceLink companyId={companyId || ''} reportFamily="tax" filters={{ tax_kind: 'output_vat', date_from: periodStart, date_to: periodEnd }} title="Open contributing output VAT sources">
              {fmt(totalVat)}
            </ReportTraceLink>
          </p>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Doc No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Exempt</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Zero-Rated</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Output VAT</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={8} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No sales transactions in this period.'}</td></tr>
              ) : filtered.map(r => (
                <tr key={r.transaction_id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.invoice_date}</td>
                  <td className="px-4 py-2.5 text-gray-700">
                    {r.system_no ? (
                      <AccountingTraceLink sourceType={r.source_doc_type} sourceId={r.source_doc_id} title="Open source accounting trace">
                        {r.system_no}
                      </AccountingTraceLink>
                    ) : '—'}
                  </td>
                  <td className="px-4 py-2.5 text-gray-700">{r.customer_name || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.gross_sales)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-500">{fmt(r.exempt_sales)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-500">{fmt(r.zero_rated_sales)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxable_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.output_vat)}</td>
                </tr>
              ))}
            </tbody>
            {filtered.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {filtered.length} transaction{filtered.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalGross)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalExempt)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalZero)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalTaxable)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">
                    <ReportTraceLink companyId={companyId || ''} reportFamily="tax" filters={{ tax_kind: 'output_vat', date_from: periodStart, date_to: periodEnd }} title="Open contributing output VAT sources">
                      {fmt(totalVat)}
                    </ReportTraceLink>
                  </td>
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
