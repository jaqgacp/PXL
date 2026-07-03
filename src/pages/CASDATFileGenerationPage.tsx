import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type ReportType = 'slsp' | 'relief' | 'general_ledger' | 'alphalist_payees'
type LogRow = { id: string; report_name: string; period_year: number; period_month: number | null; file_name: string; row_count: number; generated_at: string }

const REPORT_LABELS: Record<ReportType, string> = { slsp: 'SLSP (Sales & Purchases)', relief: 'RELIEF Listing', general_ledger: 'General Ledger', alphalist_payees: 'Alphalist of Payees (QAP)' }
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function CASDATFileGenerationPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [reportType, setReportType] = useState<ReportType>('slsp')
  const [year, setYear] = useState(now.getFullYear())
  const [month, setMonth] = useState(now.getMonth())
  const [generating, setGenerating] = useState(false)
  const [logs, setLogs] = useState<LogRow[]>([])
  const [loading, setLoading] = useState(false)

  const loadLogs = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('cas_export_log').select('id,report_name,period_year,period_month,file_name,row_count,generated_at')
      .eq('company_id', companyId).eq('export_type', 'dat_file').order('generated_at', { ascending: false }).limit(20)
    setLogs((data as LogRow[]) || [])
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) loadLogs() }, [loadLogs, companyId])

  const downloadCSV = (rows: (string | number)[][], filename: string) => {
    const csv = rows.map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = filename; a.click()
    URL.revokeObjectURL(url)
  }

  const generate = async () => {
    if (!companyId) return
    setGenerating(true)
    const fileName = `${reportType}-${MONTHS[month]}-${year}.csv`

    // The RPC builds the payload server-side, gates on reconciliation, creates
    // the immutable report snapshot + cas_export_log row, and returns the
    // frozen rows — so the downloaded file is provably the hashed payload.
    const { data, error } = await supabase.rpc('fn_snapshot_cas_export', {
      p_company_id: companyId,
      p_report_type: reportType,
      p_year: year,
      p_month: month + 1,
      p_file_name: fileName,
    })
    if (error) {
      setGenerating(false)
      alert(error.message)
      return
    }

    const payload = data as { rows: Record<string, string | number | null>[] }
    const rows = payload.rows || []
    const num = (v: string | number | null) => Number(v ?? 0).toFixed(2)
    const str = (v: string | number | null) => (v ?? '') as string

    if (reportType === 'slsp') {
      downloadCSV([['Date', 'Doc No.', 'TIN', 'Name', 'Taxable Base', 'VAT'],
        ...rows.map(r => [str(r.invoice_date), str(r.system_no), str(r.customer_tin), str(r.customer_name), num(r.taxable_base), num(r.output_vat)])], fileName)
    } else if (reportType === 'relief') {
      downloadCSV([['Date', 'Doc No.', 'TIN', 'Name', 'Taxable Base', 'VAT'],
        ...rows.map(r => [str(r.invoice_date), str(r.system_no), str(r.supplier_tin), str(r.supplier_name), num(r.taxable_base), num(r.input_vat)])], fileName)
    } else if (reportType === 'general_ledger') {
      downloadCSV([['Date', 'JE No.', 'Account Code', 'Account Name', 'Debit', 'Credit'],
        ...rows.map(r => [str(r.je_date), str(r.je_number), str(r.account_code), str(r.account_name), num(r.debit_amount), num(r.credit_amount)])], fileName)
    } else {
      downloadCSV([['Date', 'TIN', 'Name', 'ATC', 'Tax Base', 'Tax Withheld'],
        ...rows.map(r => [str(r.invoice_date), str(r.supplier_tin), str(r.supplier_name), str(r.atc_code), num(r.tax_base), num(r.tax_withheld)])], fileName)
    }

    setGenerating(false)
    loadLogs()
  }

  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">DAT File Generation</h1>
        <p className="text-sm text-gray-500 mt-0.5">Generate structured data extracts for BIR CAS submission</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={reportType} onChange={e => setReportType(e.target.value as ReportType)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          {Object.entries(REPORT_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select value={month} onChange={e => setMonth(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}</select>
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <button onClick={generate} disabled={generating || !companyId} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{generating ? 'Generating...' : '⚡ Generate & Download'}</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Recent Generations</h2></div>
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Generated</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Report</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">File</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rows</th>
              </tr>
            </thead>
            <tbody>
              {logs.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-12 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No DAT files generated yet.'}</td></tr>
              ) : logs.map(l => (
                <tr key={l.id} className="border-b border-gray-100">
                  <td className="px-4 py-2 text-xs text-gray-500">{new Date(l.generated_at).toLocaleString('en-PH')}</td>
                  <td className="px-4 py-2 text-gray-700">{l.report_name}</td>
                  <td className="px-4 py-2 text-gray-600">{l.period_month ? `${MONTHS[l.period_month - 1]} ${l.period_year}` : l.period_year}</td>
                  <td className="px-4 py-2 text-gray-700 font-mono text-xs">{l.file_name}</td>
                  <td className="px-4 py-2 text-right text-gray-700">{l.row_count}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
