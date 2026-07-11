import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AccountingTraceLink, ReportTraceLink } from '@/components/AccountingTraceLink'


type InputVATRow = {
  transaction_id: string; source_module: string; invoice_date: string
  source_doc_type: string; source_doc_id: string
  supplier_tin: string | null; supplier_name: string; invoice_no: string | null
  system_no: string; gross_purchases: number; exempt_purchases: number
  zero_rated: number; taxable_base: number; input_vat: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function InputVATReviewPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [month, setMonth] = useState(now.getMonth() + 1)
  const [rows, setRows] = useState<InputVATRow[]>([])
  const [loading, setLoading] = useState(false)
  const [supplierSearch, setSupplierSearch] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${year}-${String(month).padStart(2, '0')}-01`
    const endDate = new Date(year, month, 0).toISOString().split('T')[0]
    const { data } = await supabase.from('vw_input_vat_review')
      .select('transaction_id,source_module,invoice_date,source_doc_type,source_doc_id,supplier_tin,supplier_name,invoice_no,system_no,gross_purchases,exempt_purchases,zero_rated,taxable_base,input_vat').eq('company_id', companyId)
      .gte('invoice_date', startDate).lte('invoice_date', endDate)
      .order('invoice_date').order('supplier_name')
    setRows(data as unknown as InputVATRow[] || [])
    setLoading(false)
  }, [companyId, year, month])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const filtered = supplierSearch
    ? rows.filter(r => r.supplier_name.toLowerCase().includes(supplierSearch.toLowerCase()) || (r.supplier_tin || '').includes(supplierSearch))
    : rows

  const totals = filtered.reduce((acc, r) => ({
    gross: acc.gross + r.gross_purchases,
    exempt: acc.exempt + r.exempt_purchases,
    zero: acc.zero + r.zero_rated,
    taxable: acc.taxable + r.taxable_base,
    vat: acc.vat + r.input_vat,
  }), { gross: 0, exempt: 0, zero: 0, taxable: 0, vat: 0 })
  const periodStart = `${year}-${String(month).padStart(2, '0')}-01`
  const periodEnd = new Date(year, month, 0).toISOString().split('T')[0]

  const exportCSV = () => {
    const headers = ['Invoice Date','Supplier TIN','Registered Name','Supplier Address','Invoice No.','System No.','Gross Purchases','Exempt','Zero-Rated','Taxable Base','Input VAT']
    const csvRows = filtered.map(r => [r.invoice_date, r.supplier_tin || '', r.supplier_name, '', r.invoice_no || '', r.system_no, r.gross_purchases, r.exempt_purchases, r.zero_rated, r.taxable_base, r.input_vat].join(','))
    const csv = [headers.join(','), ...csvRows].join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }))
    a.download = `InputVAT_${year}_${String(month).padStart(2, '0')}.csv`
    a.click()
  }

  const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']
  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900'

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Input VAT Review</h2>
        <button onClick={exportCSV} className="px-3 py-1.5 text-xs border border-gray-300 rounded-md hover:bg-gray-50">Export CSV</button>
      </div>

      <div className="flex gap-3 flex-wrap">
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Year</label>
          <select value={year} onChange={e => setYear(+e.target.value)} className={inp}>
            {[now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1].map(y => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Month</label>
          <select value={month} onChange={e => setMonth(+e.target.value)} className={inp}>
            {MONTHS.map((m, i) => <option key={i + 1} value={i + 1}>{m}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Supplier</label>
          <input type="text" value={supplierSearch} onChange={e => setSupplierSearch(e.target.value)} placeholder="Filter by name or TIN…" className={inp + ' w-52'} />
        </div>
      </div>

      {/* KPI Strip */}
      <div className="grid grid-cols-4 gap-3">
        {[
          { label: 'Gross Purchases', value: totals.gross, color: 'text-gray-900' },
          { label: 'Exempt', value: totals.exempt, color: 'text-gray-600' },
          { label: 'Zero-Rated', value: totals.zero, color: 'text-blue-600' },
          { label: 'Input VAT Claimed', value: totals.vat, color: 'text-green-700' },
        ].map(({ label, value, color }) => (
          <div key={label} className="bg-white border border-gray-200 rounded-lg p-3">
            <p className="text-xs text-gray-500">{label}</p>
            <p className={`text-base font-semibold font-mono mt-0.5 ${color}`}>{fmt(value)}</p>
          </div>
        ))}
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : filtered.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No Input VAT records for this period.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Date','Supplier TIN','Supplier Name','Invoice No.','System #','Gross','Exempt','Zero-Rated','Taxable','Input VAT'].map(h => (
                  <th key={h} className={`px-3 py-2 font-medium text-gray-500 ${['Gross','Exempt','Zero-Rated','Taxable','Input VAT'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtered.map((row, i) => (
                <tr key={i} className="hover:bg-gray-50">
                  <td className="px-3 py-1.5 text-gray-500">{row.invoice_date}</td>
                  <td className="px-3 py-1.5 font-mono text-gray-600">{row.supplier_tin || '—'}</td>
                  <td className="px-3 py-1.5 text-gray-700 max-w-[160px] truncate">{row.supplier_name}</td>
                  <td className="px-3 py-1.5 font-mono text-gray-500">{row.invoice_no || '—'}</td>
                  <td className="px-3 py-1.5 font-mono text-gray-600">
                    <AccountingTraceLink sourceType={row.source_doc_type} sourceId={row.source_doc_id} title="Open source accounting trace">
                      {row.system_no}
                    </AccountingTraceLink>
                  </td>
                  <td className="px-3 py-1.5 text-right font-mono">{fmt(row.gross_purchases)}</td>
                  <td className="px-3 py-1.5 text-right font-mono text-gray-500">{row.exempt_purchases > 0 ? fmt(row.exempt_purchases) : '—'}</td>
                  <td className="px-3 py-1.5 text-right font-mono text-blue-600">{row.zero_rated > 0 ? fmt(row.zero_rated) : '—'}</td>
                  <td className="px-3 py-1.5 text-right font-mono">{fmt(row.taxable_base)}</td>
                  <td className="px-3 py-1.5 text-right font-mono font-medium text-green-700">{fmt(row.input_vat)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot className="bg-gray-50 border-t-2 border-gray-300 font-semibold text-xs">
              <tr>
                <td colSpan={5} className="px-3 py-2 text-right text-gray-600">Total ({filtered.length} records)</td>
                <td className="px-3 py-2 text-right font-mono">{fmt(totals.gross)}</td>
                <td className="px-3 py-2 text-right font-mono text-gray-500">{fmt(totals.exempt)}</td>
                <td className="px-3 py-2 text-right font-mono text-blue-600">{fmt(totals.zero)}</td>
                <td className="px-3 py-2 text-right font-mono">{fmt(totals.taxable)}</td>
                <td className="px-3 py-2 text-right font-mono text-green-700">
                  <ReportTraceLink
                    companyId={companyId || ''}
                    reportFamily="tax"
                    filters={{ tax_kind: 'input_vat', date_from: periodStart, date_to: periodEnd }}
                    title="Open contributing input VAT sources"
                    className="text-green-700 hover:text-green-900"
                  >
                    {fmt(totals.vat)}
                  </ReportTraceLink>
                </td>
              </tr>
            </tfoot>
          </table>
        )}
      </div>
    </div>
  )
}
