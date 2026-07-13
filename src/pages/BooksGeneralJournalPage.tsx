import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadCsvText, getSnapshotExportText } from '@/lib/exportDownload'

type Row = {
  line_id: string
  je_date: string
  je_number: string
  je_description: string | null
  account_code: string
  account_name: string
  line_description: string | null
  debit_amount: number
  credit_amount: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }

export default function BooksGeneralJournalPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('vw_general_ledger')
      .select('line_id,je_date,je_number,je_description,account_code,account_name,line_description,debit_amount,credit_amount')
      .eq('company_id', companyId).gte('je_date', dateFrom).lte('je_date', dateTo)
      .order('je_date').order('je_number').order('line_number')
    setRows((data as Row[]) || [])
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalDebit = rows.reduce((s, r) => s + r.debit_amount, 0)
  const totalCredit = rows.reduce((s, r) => s + r.credit_amount, 0)

  const exportCSV = async () => {
    if (!companyId) return
    setExporting(true)
    const fileName = `general-journal-${dateFrom}-to-${dateTo}.csv`
    // Server-side snapshot: freezes the exact export text with a SHA-256 hash
    // and returns that same text for download.
    const { data, error } = await supabase.rpc('fn_snapshot_books_export', {
      p_company_id: companyId,
      p_book_type: 'general_journal',
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
          <h1 className="text-xl font-semibold text-gray-900">General Journal</h1>
          <p className="text-sm text-gray-500 mt-0.5">All posted journal entries in chronological order — BIR Book of Accounts</p>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">JE No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Account</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Debit</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Credit</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No posted journal entries in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.line_id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.je_date}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono">{r.je_number}</td>
                  <td className="px-4 py-2 text-gray-700">{r.account_code} — {r.account_name}</td>
                  <td className="px-4 py-2 text-gray-600">{r.line_description || r.je_description || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{r.debit_amount > 0 ? fmt(r.debit_amount) : ''}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{r.credit_amount > 0 ? fmt(r.credit_amount) : ''}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} line{rows.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalDebit)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalCredit)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
