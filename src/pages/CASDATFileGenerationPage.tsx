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
    const startDate = `${year}-${String(month + 1).padStart(2, '0')}-01`
    const endDate = new Date(year, month + 1, 0).toISOString().split('T')[0]
    const fileName = `${reportType}-${MONTHS[month]}-${year}.csv`
    let rowCount = 0

    if (reportType === 'slsp') {
      const { data } = await supabase.from('vw_output_vat_review').select('*').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)
      const rows = (data || []) as { invoice_date: string; system_no: string | null; customer_tin: string | null; customer_name: string | null; taxable_base: number; output_vat: number }[]
      downloadCSV([['Date', 'Doc No.', 'TIN', 'Name', 'Taxable Base', 'VAT'], ...rows.map(r => [r.invoice_date, r.system_no || '', r.customer_tin || '', r.customer_name || '', r.taxable_base.toFixed(2), r.output_vat.toFixed(2)])], fileName)
      rowCount = rows.length
    } else if (reportType === 'relief') {
      const { data } = await supabase.from('vw_input_vat_review').select('*').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)
      const rows = (data || []) as { invoice_date: string; system_no: string | null; supplier_tin: string | null; supplier_name: string | null; taxable_base: number; input_vat: number }[]
      downloadCSV([['Date', 'Doc No.', 'TIN', 'Name', 'Taxable Base', 'VAT'], ...rows.map(r => [r.invoice_date, r.system_no || '', r.supplier_tin || '', r.supplier_name || '', r.taxable_base.toFixed(2), r.input_vat.toFixed(2)])], fileName)
      rowCount = rows.length
    } else if (reportType === 'general_ledger') {
      const { data } = await supabase.from('vw_general_ledger').select('*').eq('company_id', companyId).gte('je_date', startDate).lte('je_date', endDate)
      const rows = (data || []) as { je_date: string; je_number: string; account_code: string; account_name: string; debit_amount: number; credit_amount: number }[]
      downloadCSV([['Date', 'JE No.', 'Account Code', 'Account Name', 'Debit', 'Credit'], ...rows.map(r => [r.je_date, r.je_number, r.account_code, r.account_name, r.debit_amount.toFixed(2), r.credit_amount.toFixed(2)])], fileName)
      rowCount = rows.length
    } else {
      const { data } = await supabase.from('vw_ewt_summary_ap').select('*').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)
      const rows = (data || []) as { invoice_date: string; supplier_tin: string | null; supplier_name: string | null; atc_code: string | null; tax_base: number; tax_withheld: number }[]
      downloadCSV([['Date', 'TIN', 'Name', 'ATC', 'Tax Base', 'Tax Withheld'], ...rows.map(r => [r.invoice_date, r.supplier_tin || '', r.supplier_name || '', r.atc_code || '', r.tax_base.toFixed(2), r.tax_withheld.toFixed(2)])], fileName)
      rowCount = rows.length
    }

    await supabase.from('cas_export_log').insert([{
      company_id: companyId, export_type: 'dat_file', report_name: REPORT_LABELS[reportType],
      period_year: year, period_month: month + 1, file_name: fileName, row_count: rowCount,
    }])

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
