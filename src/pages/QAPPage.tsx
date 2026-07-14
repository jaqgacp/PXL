import { useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  supplier_id: string | null
  supplier_name: string | null
  supplier_tin: string | null
  atc_code: string | null
  nature_of_payment: string | null
  tax_rate: number | null
  tax_base: number
  tax_withheld: number
}
type Agg = {
  key: string
  supplier_id: string | null
  supplier_name: string
  supplier_tin: string
  atc_code: string
  nature_of_payment: string
  tax_rate: number
  tax_base: number
  tax_withheld: number
}
type QapPayloadRow = Partial<Agg> & {
  supplier_id?: string | null
  supplier_name?: string | null
  supplier_tin?: string | null
  atc_code?: string | null
  nature_of_payment?: string | null
  tax_rate?: number | string | null
  tax_base?: number | string | null
  tax_withheld?: number | string | null
}
type QapSnapshotPayload = { payee_summary_rows?: QapPayloadRow[] }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }
const quarterDates = (year: number, quarter: number) => {
  const months = QUARTERS[quarter]
  return {
    dateFrom: `${year}-${String(months[0]).padStart(2, '0')}-01`,
    dateTo: new Date(year, months[2], 0).toISOString().split('T')[0],
  }
}

export default function QAPPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [rows, setRows] = useState<Agg[]>([])
  const { dateFrom, dateTo } = quarterDates(year, quarter)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const { data } = await supabase.from('vw_ewt_summary_ap').select('supplier_id,supplier_name,supplier_tin,atc_code,nature_of_payment,tax_rate,tax_base,tax_withheld')
      .eq('company_id', companyId).gte('invoice_date', dateFrom).lte('invoice_date', dateTo)

    const bySupplierAtc: Record<string, Agg> = {}
    for (const r of (data || []) as Row[]) {
      const atc = r.atc_code || ''
      const nature = r.nature_of_payment || ''
      const rate = Number(r.tax_rate || 0)
      const key = [r.supplier_id || r.supplier_tin || 'unknown', atc, nature, rate.toFixed(2)].join('|')
      if (!bySupplierAtc[key]) {
        bySupplierAtc[key] = {
          key,
          supplier_id: r.supplier_id,
          supplier_name: r.supplier_name || 'Unknown',
          supplier_tin: r.supplier_tin || '',
          atc_code: atc,
          nature_of_payment: nature,
          tax_rate: rate,
          tax_base: 0,
          tax_withheld: 0,
        }
      }
      bySupplierAtc[key].tax_base += Number(r.tax_base)
      bySupplierAtc[key].tax_withheld += Number(r.tax_withheld)
    }
    setRows(Object.values(bySupplierAtc).sort((a, b) =>
      a.supplier_name.localeCompare(b.supplier_name) ||
      a.atc_code.localeCompare(b.atc_code) ||
      a.nature_of_payment.localeCompare(b.nature_of_payment)
    ))
    setLoading(false)
  }, [companyId, dateFrom, dateTo])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalBase = rows.reduce((s, r) => s + r.tax_base, 0)
  const totalWithheld = rows.reduce((s, r) => s + r.tax_withheld, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)
  const qapTraceFilters = (row: Agg) => ({
    tax_kind: 'ewt_payable',
    counterparty_id: row.supplier_id || undefined,
    atc_code: row.atc_code || undefined,
    income_nature: row.nature_of_payment || undefined,
    tax_rate: String(row.tax_rate),
    active_only: 'true',
    date_from: dateFrom,
    date_to: dateTo,
  })

  const exportCSV = async () => {
    if (!companyId) return
    setExporting(true)
    const { data: snapshotId, error } = await supabase.rpc('fn_snapshot_wht_export', {
      p_company_id: companyId,
      p_report_type: 'QAP',
      p_year: year,
      p_quarter: quarter,
    })
    if (error) {
      setExporting(false)
      alert(error.message)
      return
    }
    const { data: snapshot, error: snapshotError } = await supabase
      .from('report_snapshots')
      .select('source_payload')
      .eq('id', snapshotId)
      .single()
    setExporting(false)
    if (snapshotError) {
      alert(snapshotError.message)
      return
    }
    const payload = snapshot?.source_payload as QapSnapshotPayload | null
    const exportRows = (payload?.payee_summary_rows || rows).map(r => ({
      supplier_tin: r.supplier_tin || '',
      supplier_name: r.supplier_name || 'Unknown',
      atc_code: r.atc_code || '',
      nature_of_payment: r.nature_of_payment || '',
      tax_rate: Number(r.tax_rate || 0),
      tax_base: Number(r.tax_base || 0),
      tax_withheld: Number(r.tax_withheld || 0),
    }))
    const header = ['TIN', 'Registered Name', 'ATC', 'Nature of Payment', 'Rate', 'Income Payments', 'Tax Withheld']
    const csvRows = exportRows.map(r => [r.supplier_tin, r.supplier_name, r.atc_code, r.nature_of_payment, r.tax_rate.toFixed(2), r.tax_base.toFixed(2), r.tax_withheld.toFixed(2)])
    const csv = [header, ...csvRows].map(row => row.map(c => `"${c}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `qap-Q${quarter}-${year}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">QAP — Quarterly Alphalist of Payees</h1>
          <p className="text-sm text-gray-500 mt-0.5">Per-supplier EWT summary — attachment to 1601EQ filing</p>
        </div>
        <button onClick={exportCSV} disabled={exporting || rows.length === 0} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{exporting ? 'Exporting...' : '↓ Export CSV'}</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATC</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Nature</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Income Payments</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Withheld</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No EWT payees in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.key} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">
                    {r.supplier_id ? (
                      <ReportTraceLink
                        companyId={companyId || ''}
                        reportFamily="tax"
                        filters={qapTraceFilters(r)}
                        title="Open the accounting sources included for this QAP payee/ATC row"
                      >
                        {r.supplier_name}
                      </ReportTraceLink>
                    ) : r.supplier_name}
                  </td>
                  <td className="px-4 py-2.5 text-gray-500 font-mono">{r.atc_code || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-500">{r.nature_of_payment || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax_rate)}%</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">
                    {r.supplier_id ? (
                      <ReportTraceLink
                        companyId={companyId || ''}
                        reportFamily="tax"
                        filters={qapTraceFilters(r)}
                        title="Open the tax-ledger sources for this QAP withholding amount"
                      >
                        {fmt(r.tax_withheld)}
                      </ReportTraceLink>
                    ) : fmt(r.tax_withheld)}
                  </td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} payee/ATC row{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBase)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalWithheld)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
