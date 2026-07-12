import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  source_id: string
  document_date: string | null
  occurred_at: string
  document_code: string
  document_number: string
  party_name: string | null
  document_amount: number | null
  terminal_status: string
  reason_text: string
  reversal_journal_entry_id: string | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
}).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

export default function CASDocumentVoidRegisterPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const run = useCallback(async () => {
    if (!companyId) {
      setRows([])
      return
    }
    setLoading(true)
    setError('')

    const { data, error: queryError } = await supabase
      .from('cas_document_void_events')
      .select('id,source_id,document_date,occurred_at,document_code,document_number,party_name,document_amount,terminal_status,reason_text,reversal_journal_entry_id')
      .eq('company_id', companyId)
      .gte('occurred_at', `${dateFrom}T00:00:00`)
      .lte('occurred_at', `${dateTo}T23:59:59.999999`)
      .order('occurred_at', { ascending: true })
      .order('document_code', { ascending: true })
      .order('document_number', { ascending: true })

    if (queryError) {
      setRows([])
      setError(queryError.message)
    } else {
      setRows((data as Row[]) || [])
    }
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { run() }, [run])

  const total = rows.reduce((sum, row) => sum + Number(row.document_amount || 0), 0)

  const exportCSV = () => {
    const header = [
      'Voided At', 'Document Date', 'Document Code', 'Document No.', 'Party',
      'Amount', 'Terminal Status', 'Reason', 'Source ID', 'Reversal JE ID',
    ]
    const csvRows = rows.map(row => [
      row.occurred_at,
      row.document_date || '',
      row.document_code,
      row.document_number,
      row.party_name || '',
      Number(row.document_amount || 0).toFixed(2),
      row.terminal_status,
      row.reason_text,
      row.source_id,
      row.reversal_journal_entry_id || '',
    ])
    const csv = [header, ...csvRows]
      .map(row => row.map(value => `"${String(value).replace(/"/g, '""')}"`).join(','))
      .join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `document-void-register-${dateFrom}-to-${dateTo}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Document Void Register</h1>
          <p className="text-sm text-gray-500 mt-0.5">Immutable void, cancellation, bounce, and reversal evidence captured by the database</p>
        </div>
        <button onClick={exportCSV} disabled={rows.length === 0}
          className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">
          ↓ Export CSV
        </button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <input type="date" value={dateFrom} onChange={event => setDateFrom(event.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
        <span className="text-xs text-gray-400">voided through</span>
        <input type="date" value={dateTo} onChange={event => setDateTo(event.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}

      <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                {['Voided At', 'Document Date', 'Type', 'Document No.', 'Party', 'Amount', 'Status', 'Reason', 'Reversal JE'].map(label => (
                  <th key={label} className={`px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap ${label === 'Amount' ? 'text-right' : 'text-left'}`}>{label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={9} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No governed void events in this period.'}</td></tr>
              ) : rows.map(row => (
                <tr key={row.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{new Date(row.occurred_at).toLocaleString('en-PH')}</td>
                  <td className="px-4 py-2 text-gray-700 whitespace-nowrap">{row.document_date || '—'}</td>
                  <td className="px-4 py-2 text-gray-500 font-mono">{row.document_code}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono whitespace-nowrap">{row.document_number}</td>
                  <td className="px-4 py-2 text-gray-700">{row.party_name || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(Number(row.document_amount || 0))}</td>
                  <td className="px-4 py-2 text-gray-600 capitalize">{row.terminal_status}</td>
                  <td className="px-4 py-2 text-gray-600 min-w-52">{row.reason_text}</td>
                  <td className="px-4 py-2 text-xs text-gray-500 font-mono">{row.reversal_journal_entry_id ? row.reversal_journal_entry_id.slice(0, 8) : '—'}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} governed event{rows.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(total)}</td>
                  <td colSpan={3} />
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
