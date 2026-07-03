import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { id: string; date: string; doc_type: 'PV' | 'CV' | 'CP'; doc_number: string; payee: string; amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }
const DOC_LABEL: Record<Row['doc_type'], string> = { PV: 'Payment Voucher', CV: 'Check Voucher', CP: 'Cash Purchase' }

export default function BooksCashDisbursementsPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: pvData }, { data: cvData }, { data: cpData }] = await Promise.all([
      supabase.from('payment_vouchers').select('id,voucher_date,voucher_number,supplier_name_snapshot,total_amount,total_ewt')
        .eq('company_id', companyId).eq('status', 'posted').gte('voucher_date', dateFrom).lte('voucher_date', dateTo),
      supabase.from('check_vouchers').select('id,voucher_date,cv_number,payee,net_check_amount')
        .eq('company_id', companyId).eq('status', 'posted').gte('voucher_date', dateFrom).lte('voucher_date', dateTo),
      supabase.from('cash_purchases').select('id,transaction_date,cp_number,supplier_name_snapshot,total_amount')
        .eq('company_id', companyId).eq('status', 'posted').gte('transaction_date', dateFrom).lte('transaction_date', dateTo),
    ])

    const pvRows: Row[] = ((pvData || []) as { id: string; voucher_date: string; voucher_number: string; supplier_name_snapshot: string; total_amount: number; total_ewt: number }[])
      .map(r => ({ id: r.id, date: r.voucher_date, doc_type: 'PV', doc_number: r.voucher_number, payee: r.supplier_name_snapshot, amount: Number(r.total_amount) - Number(r.total_ewt || 0) }))
    const cvRows: Row[] = ((cvData || []) as { id: string; voucher_date: string; cv_number: string; payee: string; net_check_amount: number }[])
      .map(r => ({ id: r.id, date: r.voucher_date, doc_type: 'CV', doc_number: r.cv_number, payee: r.payee, amount: Number(r.net_check_amount) }))
    const cpRows: Row[] = ((cpData || []) as { id: string; transaction_date: string; cp_number: string; supplier_name_snapshot: string | null; total_amount: number }[])
      .map(r => ({ id: r.id, date: r.transaction_date, doc_type: 'CP', doc_number: r.cp_number, payee: r.supplier_name_snapshot || 'Cash Purchase', amount: Number(r.total_amount) }))

    const combined = [...pvRows, ...cvRows, ...cpRows].sort((a, b) => a.date < b.date ? -1 : 1)
    setRows(combined)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const total = rows.reduce((s, r) => s + r.amount, 0)

  const exportCSV = async () => {
    if (!companyId) return
    setExporting(true)
    const fileName = `cash-disbursements-book-${dateFrom}-to-${dateTo}.csv`
    // Server-side snapshot: freezes the book payload with a SHA-256 hash and
    // returns the frozen rows, so the file is provably the hashed payload.
    const { data, error } = await supabase.rpc('fn_snapshot_books_export', {
      p_company_id: companyId,
      p_book_type: 'cash_disbursements',
      p_date_from: dateFrom,
      p_date_to: dateTo,
      p_file_name: fileName,
    })
    setExporting(false)
    if (error) {
      alert(error.message)
      return
    }
    const frozen = ((data as { rows: Record<string, string | number | null>[] }).rows) || []
    const num = (v: string | number | null) => Number(v ?? 0).toFixed(2)
    const str = (v: string | number | null) => (v ?? '') as string
    const header = ['Date', 'Type', 'Doc No.', 'Payee', 'Amount']
    const csvRows = frozen.map(r => [str(r.date), DOC_LABEL[str(r.doc_type) as Row['doc_type']], str(r.doc_number), str(r.payee), num(r.amount)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = fileName; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Cash Disbursements Book</h1>
          <p className="text-sm text-gray-500 mt-0.5">Payment Vouchers, Check Vouchers &amp; Cash Purchases — BIR Book of Accounts</p>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Doc No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Payee</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No cash disbursements in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={`${r.doc_type}-${r.id}`} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.date}</td>
                  <td className="px-4 py-2 text-gray-500">{DOC_LABEL[r.doc_type]}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono">{r.doc_number}</td>
                  <td className="px-4 py-2 text-gray-700">{r.payee}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.amount)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} disbursement{rows.length !== 1 ? 's' : ''}</td>
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
