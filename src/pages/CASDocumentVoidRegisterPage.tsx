import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = { id: string; date: string; doc_type: string; doc_number: string; party: string; amount: number; reason: string }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }

export default function CASDocumentVoidRegisterPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: siData }, { data: vbData }, { data: pvData }, { data: jeData }] = await Promise.all([
      supabase.from('sales_invoices').select('id,date,si_number,customer_name_snapshot,total_amount,void_reason_codes(description)')
        .eq('company_id', companyId).eq('status', 'cancelled').gte('date', dateFrom).lte('date', dateTo),
      supabase.from('vendor_bills').select('id,bill_date,bill_number,supplier_name_snapshot,total_amount,void_reason_codes(description)')
        .eq('company_id', companyId).eq('status', 'cancelled').gte('bill_date', dateFrom).lte('bill_date', dateTo),
      supabase.from('payment_vouchers').select('id,voucher_date,voucher_number,supplier_name_snapshot,total_amount,remarks')
        .eq('company_id', companyId).eq('status', 'cancelled').gte('voucher_date', dateFrom).lte('voucher_date', dateTo),
      supabase.from('journal_entries').select('id,je_date,je_number,description,total_debit')
        .eq('company_id', companyId).eq('status', 'reversed').gte('je_date', dateFrom).lte('je_date', dateTo),
    ])

    const siRows: Row[] = ((siData || []) as unknown as { id: string; date: string; si_number: string; customer_name_snapshot: string; total_amount: number; void_reason_codes: { description: string } | null }[])
      .map(r => ({ id: r.id, date: r.date, doc_type: 'Sales Invoice', doc_number: r.si_number, party: r.customer_name_snapshot, amount: Number(r.total_amount), reason: r.void_reason_codes?.description || '—' }))
    const vbRows: Row[] = ((vbData || []) as unknown as { id: string; bill_date: string; bill_number: string; supplier_name_snapshot: string; total_amount: number; void_reason_codes: { description: string } | null }[])
      .map(r => ({ id: r.id, date: r.bill_date, doc_type: 'Vendor Bill', doc_number: r.bill_number, party: r.supplier_name_snapshot, amount: Number(r.total_amount), reason: r.void_reason_codes?.description || '—' }))
    const pvRows: Row[] = ((pvData || []) as { id: string; voucher_date: string; voucher_number: string; supplier_name_snapshot: string; total_amount: number; remarks: string | null }[])
      .map(r => ({ id: r.id, date: r.voucher_date, doc_type: 'Payment Voucher', doc_number: r.voucher_number, party: r.supplier_name_snapshot, amount: Number(r.total_amount), reason: r.remarks || '—' }))
    const jeRows: Row[] = ((jeData || []) as { id: string; je_date: string; je_number: string; description: string | null; total_debit: number }[])
      .map(r => ({ id: r.id, date: r.je_date, doc_type: 'Journal Entry (Reversed)', doc_number: r.je_number, party: '—', amount: Number(r.total_debit), reason: r.description || 'Reversed' }))

    const combined = [...siRows, ...vbRows, ...pvRows, ...jeRows].sort((a, b) => a.date < b.date ? -1 : 1)
    setRows(combined)
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const total = rows.reduce((s, r) => s + r.amount, 0)

  const exportCSV = () => {
    const header = ['Date', 'Document Type', 'Doc No.', 'Party', 'Amount', 'Reason']
    const csvRows = rows.map(r => [r.date, r.doc_type, r.doc_number, r.party, r.amount.toFixed(2), r.reason])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `document-void-register-${dateFrom}-to-${dateTo}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Document Void Register</h1>
          <p className="text-sm text-gray-500 mt-0.5">Voided/cancelled invoices, bills, payment vouchers &amp; reversed journal entries</p>
        </div>
        <button onClick={exportCSV} disabled={rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">↓ Export CSV</button>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Document Type</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Doc No.</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Party</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reason</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No voided documents in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={`${r.doc_type}-${r.id}`} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.date}</td>
                  <td className="px-4 py-2 text-gray-500">{r.doc_type}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono">{r.doc_number}</td>
                  <td className="px-4 py-2 text-gray-700">{r.party}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.amount)}</td>
                  <td className="px-4 py-2 text-gray-600">{r.reason}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} voided document{rows.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(total)}</td>
                  <td />
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
