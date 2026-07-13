import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadCsvText, getSnapshotExportText } from '@/lib/exportDownload'

type Row = { id: string; date: string; si_number: string; customer_name_snapshot: string; customer_tin_snapshot: string | null; total_amount: number; total_vat_amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }

export default function BooksCashSalesJournalPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('sales_invoices')
      .select('id,date,si_number,customer_name_snapshot,customer_tin_snapshot,total_amount,total_vat_amount')
      .eq('company_id', companyId).eq('status', 'posted').eq('is_cash_sale', true)
      .gte('date', dateFrom).lte('date', dateTo).order('date').order('si_number')
    setRows((data as Row[]) || [])
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const total = rows.reduce((s, r) => s + r.total_amount, 0)
  const totalVat = rows.reduce((s, r) => s + r.total_vat_amount, 0)

  const exportCSV = async () => {
    if (!companyId) return
    setExporting(true)
    const fileName = `cash-sales-journal-${dateFrom}-to-${dateTo}.csv`
    // Server-side snapshot: freezes the exact export text with a SHA-256 hash
    // and returns that same text for download.
    const { data, error } = await supabase.rpc('fn_snapshot_books_export', {
      p_company_id: companyId,
      p_book_type: 'cash_sales_journal',
      p_date_from: dateFrom,
      p_date_to: dateTo,
      p_file_name: fileName,
    })
    setExporting(false)
    if (error) {
      alert(error.message)
      return
    }
    const exportText = getSnapshotExportText(data)
    if (!exportText) {
      alert('Books export did not return a file payload.')
      return
    }
    downloadCsvText(exportText, fileName)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Cash Sales Journal</h1>
          <p className="text-sm text-gray-500 mt-0.5">Cash sales invoices — BIR Book of Accounts</p>
        </div>
        <div className="flex gap-2">
          <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
          <button onClick={exportCSV} disabled={exporting || rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{exporting ? 'Exporting...' : '↓ Export CSV'}</button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">to</span>
        <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">SI No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">VAT</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Total</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No cash sales in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.date}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono">{r.si_number}</td>
                  <td className="px-4 py-2 text-gray-700">{r.customer_name_snapshot}</td>
                  <td className="px-4 py-2 text-gray-500">{r.customer_tin_snapshot || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(r.total_vat_amount)}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.total_amount)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} invoice{rows.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalVat)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(total)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
