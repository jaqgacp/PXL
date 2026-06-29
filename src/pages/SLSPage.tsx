import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────────────────────
type SLSRow = {
  id: string; si_number: string; date: string
  customer_name_snapshot: string; customer_tin_snapshot: string | null
  customer_address_snapshot: string | null
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_vat_amount: number; total_amount: number
  status: string
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const QUARTERS: Record<number, { label: string; months: number[] }> = {
  1: { label: 'Q1 (Jan–Mar)', months: [1, 2, 3] },
  2: { label: 'Q2 (Apr–Jun)', months: [4, 5, 6] },
  3: { label: 'Q3 (Jul–Sep)', months: [7, 8, 9] },
  4: { label: 'Q4 (Oct–Dec)', months: [10, 11, 12] },
}

function currentQuarter(): number {
  return Math.ceil((new Date().getMonth() + 1) / 3)
}

// ── Component ─────────────────────────────────────────────────────────────────
export default function SLSPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [selQ, setSelQ] = useState(currentQuarter())
  const [selYear, setSelYear] = useState(now.getFullYear())
  const [includeVoid, setIncludeVoid] = useState(false)
  const [loading, setLoading] = useState(false)
  const [rows, setRows] = useState<SLSRow[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true); setRows([])
    const months = QUARTERS[selQ].months
    const startDate = `${selYear}-${String(months[0]).padStart(2, '0')}-01`
    const lastMonth = months[months.length - 1]
    const lastDay   = new Date(selYear, lastMonth, 0).getDate()
    const endDate   = `${selYear}-${String(lastMonth).padStart(2, '0')}-${lastDay}`

    const statuses = includeVoid ? ['posted', 'cancelled'] : ['posted']

    const { data } = await supabase
      .from('sales_invoices')
      .select('id,si_number,date,customer_name_snapshot,customer_tin_snapshot,customer_address_snapshot,total_taxable_amount,total_zero_rated_amount,total_exempt_amount,total_vat_amount,total_amount,status')
      .eq('company_id', companyId)
      .in('status', statuses)
      .gte('date', startDate).lte('date', endDate)
      .order('date').order('si_number')

    setRows(data as SLSRow[] || [])
    setLoading(false)
  }, [companyId, selQ, selYear, includeVoid])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const posted = rows.filter(r => r.status === 'posted')
  const totals = {
    taxable:   posted.reduce((s, r) => s + Number(r.total_taxable_amount), 0),
    zero:      posted.reduce((s, r) => s + Number(r.total_zero_rated_amount), 0),
    exempt:    posted.reduce((s, r) => s + Number(r.total_exempt_amount), 0),
    vat:       posted.reduce((s, r) => s + Number(r.total_vat_amount), 0),
    total:     posted.reduce((s, r) => s + Number(r.total_amount), 0),
  }
  const yearRange = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    const header = [
      'Taxpayer Identification Number (TIN)',
      'Registered Name',
      'Business Address',
      'Date',
      'SI/OR Number',
      'Exempt',
      'Zero-Rated',
      'Taxable Sales',
      'Output VAT',
      'Total',
    ]
    const dataRows = rows.map(r => [
      r.customer_tin_snapshot || '',
      r.customer_name_snapshot,
      r.customer_address_snapshot || '',
      r.date,
      r.si_number,
      Number(r.total_exempt_amount).toFixed(2),
      Number(r.total_zero_rated_amount).toFixed(2),
      Number(r.total_taxable_amount).toFixed(2),
      Number(r.total_vat_amount).toFixed(2),
      Number(r.total_amount).toFixed(2),
    ])
    const csv = [header, ...dataRows].map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n')
    const a = document.createElement('a'); a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv)
    a.download = `SLS-${selYear}-Q${selQ}.csv`; a.click()
  }

  return (
    <div>
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500">Summary List of Sales (SLS)</span>
        <select value={selQ} onChange={e => setSelQ(Number(e.target.value))}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          {Object.entries(QUARTERS).map(([q, { label }]) => <option key={q} value={q}>{label}</option>)}
        </select>
        <select value={selYear} onChange={e => setSelYear(Number(e.target.value))}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          {yearRange.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        <label className="flex items-center gap-1.5 text-xs text-gray-600 cursor-pointer">
          <input type="checkbox" checked={includeVoid} onChange={e => setIncludeVoid(e.target.checked)} className="h-3.5 w-3.5" />
          Include voided
        </label>
        <button onClick={run} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">Run</button>
        {rows.length > 0 && (
          <button onClick={exportCSV} className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">
            ↓ Export CSV
          </button>
        )}
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
        <div className="ml-auto">
          <span className="text-xs text-gray-500">{rows.length} record{rows.length !== 1 ? 's' : ''}</span>
        </div>
      </div>

      {/* Quarter summary strip */}
      <div className="bg-white border-b border-gray-200 grid grid-cols-5 divide-x divide-gray-200">
        {[
          { label: 'Taxable Sales', value: totals.taxable },
          { label: 'Zero-Rated', value: totals.zero },
          { label: 'Exempt', value: totals.exempt },
          { label: 'Output VAT', value: totals.vat, accent: true },
          { label: 'Gross Sales', value: totals.total, bold: true },
        ].map(kpi => (
          <div key={kpi.label} className="px-4 py-3">
            <div className="text-[10px] font-medium text-gray-400 uppercase tracking-wide">{kpi.label}</div>
            <div className={`text-lg font-mono tabular-nums font-bold mt-0.5 ${kpi.accent ? 'text-blue-700' : 'text-gray-900'}`}>{fmt(kpi.value)}</div>
          </div>
        ))}
      </div>

      {/* BIR SLSP header note */}
      <div className="bg-amber-50 border-b border-amber-100 px-5 py-2 text-[11px] text-amber-700">
        BIR SLSP Format — {selYear} Q{selQ} · {QUARTERS[selQ].label} · Export and submit with VAT Return (2550Q)
      </div>

      {loading ? (
        <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No posted invoices</p>
          <p className="text-xs text-gray-400 mt-1">No Sales Invoices for {selYear} {QUARTERS[selQ].label}.</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Date','SI / OR Number','Customer Name','TIN','Address','Exempt','Zero-Rated','Taxable','Output VAT','Total','Status'].map(h => (
                  <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Exempt','Zero-Rated','Taxable','Output VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(r => (
                <tr key={r.id} className={`hover:bg-gray-50/50 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                  <td className="px-3 py-2 text-xs text-gray-600 whitespace-nowrap">{r.date}</td>
                  <td className={`px-3 py-2 font-mono text-xs font-semibold whitespace-nowrap ${r.status === 'cancelled' ? 'line-through text-gray-400' : 'text-gray-900'}`}>{r.si_number}</td>
                  <td className="px-3 py-2 text-xs text-gray-900 max-w-[160px] truncate">{r.customer_name_snapshot}</td>
                  <td className="px-3 py-2 font-mono text-xs text-gray-500 whitespace-nowrap">{r.customer_tin_snapshot || '—'}</td>
                  <td className="px-3 py-2 text-xs text-gray-500 max-w-[140px] truncate">{r.customer_address_snapshot || '—'}</td>
                  <td className="px-3 py-2 text-right font-mono text-xs tabular-nums text-gray-600">{r.total_exempt_amount ? fmt(Number(r.total_exempt_amount)) : '—'}</td>
                  <td className="px-3 py-2 text-right font-mono text-xs tabular-nums text-gray-600">{r.total_zero_rated_amount ? fmt(Number(r.total_zero_rated_amount)) : '—'}</td>
                  <td className="px-3 py-2 text-right font-mono text-xs tabular-nums text-gray-700">{r.total_taxable_amount ? fmt(Number(r.total_taxable_amount)) : '—'}</td>
                  <td className="px-3 py-2 text-right font-mono text-xs tabular-nums text-blue-700">{r.total_vat_amount ? fmt(Number(r.total_vat_amount)) : '—'}</td>
                  <td className="px-3 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(r.total_amount))}</td>
                  <td className="px-3 py-2">
                    <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase ${r.status === 'cancelled' ? 'bg-red-50 text-red-600' : 'bg-green-50 text-green-700'}`}>
                      {r.status === 'cancelled' ? 'Void' : 'Posted'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t-2 border-gray-300 bg-gray-50">
              <tr>
                <td colSpan={5} className="px-3 py-2.5 text-xs font-semibold text-gray-700">
                  TOTALS — {posted.length} posted invoice{posted.length !== 1 ? 's' : ''}
                </td>
                <td className="px-3 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(totals.exempt)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(totals.zero)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(totals.taxable)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-blue-700">{fmt(totals.vat)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(totals.total)}</td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
