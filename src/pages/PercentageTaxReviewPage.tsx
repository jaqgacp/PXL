import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────────────────────
type InvoiceLine = {
  id: string; si_number: string; date: string
  customer_name_snapshot: string; customer_tin_snapshot: string | null
  description: string; net_amount: number; vat_classification: string
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']
const PT_RATE = 0.03 // 3% standard BIR percentage tax rate (2551M/Q)

export default function PercentageTaxReviewPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [selMonth, setSelMonth] = useState(now.getMonth())
  const [selYear, setSelYear] = useState(now.getFullYear())
  const [loading, setLoading] = useState(false)
  const [lines, setLines] = useState<InvoiceLine[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true); setLines([])

    const startDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-01`
    const endDay    = new Date(selYear, selMonth + 1, 0).getDate()
    const endDate   = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-${endDay}`

    // Load posted SI lines that are exempt or zero-rated (PT-applicable)
    const { data } = await supabase
      .from('sales_invoice_lines')
      .select(`
        id, description, net_amount, vat_code_id,
        vat_codes!inner(vat_classification),
        sales_invoices!inner(si_number, date, customer_name_snapshot, customer_tin_snapshot, status, company_id)
      `)
      .eq('sales_invoices.company_id', companyId)
      .eq('sales_invoices.status', 'posted')
      .gte('sales_invoices.date', startDate)
      .lte('sales_invoices.date', endDate)
      .in('vat_codes.vat_classification', ['exempt', 'zero_rated'])

    const rows: InvoiceLine[] = (data || []).map((r: Record<string, unknown>) => {
      const si = r.sales_invoices as Record<string, unknown>
      const vc = r.vat_codes    as Record<string, unknown>
      return {
        id: r.id as string,
        si_number: si.si_number as string,
        date: si.date as string,
        customer_name_snapshot: si.customer_name_snapshot as string,
        customer_tin_snapshot: si.customer_tin_snapshot as string | null,
        description: r.description as string,
        net_amount: Number(r.net_amount),
        vat_classification: vc.vat_classification as string,
      }
    })
    rows.sort((a, b) => a.date < b.date ? -1 : 1)
    setLines(rows)
    setLoading(false)
  }, [companyId, selMonth, selYear])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const totalBase = lines.reduce((s, l) => s + l.net_amount, 0)
  const totalPT   = totalBase * PT_RATE
  const exemptAmt = lines.filter(l => l.vat_classification === 'exempt').reduce((s, l) => s + l.net_amount, 0)
  const zeroAmt   = lines.filter(l => l.vat_classification === 'zero_rated').reduce((s, l) => s + l.net_amount, 0)
  const yearRange = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  const exportCSV = () => {
    const header = ['Date','SI Number','Customer','TIN','Classification','Base Amount','PT Amount (3%)']
    const rows = lines.map(l => [
      l.date, l.si_number, l.customer_name_snapshot, l.customer_tin_snapshot || '',
      l.vat_classification === 'exempt' ? 'Exempt' : 'Zero-Rated',
      l.net_amount.toFixed(2), (l.net_amount * PT_RATE).toFixed(2),
    ])
    const csv = [header, ...rows].map(r => r.map(v => `"${v}"`).join(',')).join('\n')
    const a = document.createElement('a'); a.href = 'data:text/csv,' + encodeURIComponent(csv)
    a.download = `pt-review-${selYear}-${String(selMonth + 1).padStart(2, '0')}.csv`; a.click()
  }

  return (
    <div>
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <select value={selMonth} onChange={e => setSelMonth(Number(e.target.value))}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          {MONTHS.map((m, i) => <option key={i} value={i}>{m}</option>)}
        </select>
        <select value={selYear} onChange={e => setSelYear(Number(e.target.value))}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          {yearRange.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        <button onClick={run} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">Run</button>
        {lines.length > 0 && (
          <button onClick={exportCSV} className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">
            ↓ Export CSV
          </button>
        )}
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
        <div className="ml-auto text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1">
          Rate: 3% (BIR 2551Q standard) — verify against your compliance profile
        </div>
      </div>

      {/* KPI Strip */}
      <div className="bg-white border-b border-gray-200 grid grid-cols-2 md:grid-cols-4 divide-x divide-gray-200">
        {[
          { label: 'Exempt Sales', value: exemptAmt },
          { label: 'Zero-Rated Sales', value: zeroAmt },
          { label: 'Total PT Base', value: totalBase },
          { label: 'Estimated PT (3%)', value: totalPT, accent: true },
        ].map(kpi => (
          <div key={kpi.label} className="px-5 py-3">
            <div className="text-[11px] font-medium text-gray-400 uppercase tracking-wide">{kpi.label}</div>
            <div className={`text-xl font-mono tabular-nums font-bold mt-0.5 ${kpi.accent ? 'text-blue-700' : 'text-gray-900'}`}>{fmt(kpi.value)}</div>
          </div>
        ))}
      </div>

      {loading ? (
        <div className="divide-y divide-gray-100">{[...Array(5)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
      ) : lines.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No PT-applicable lines found</p>
          <p className="text-xs text-gray-400 mt-1">
            No exempt or zero-rated lines in posted invoices for {MONTHS[selMonth]} {selYear}.<br />
            Percentage Tax applies to exempt and zero-rated sales for non-VAT registered entities.
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Date','SI Number','Customer','TIN','Description','Classification','Base Amount','PT Amount (3%)'].map(h => (
                  <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Base Amount','PT Amount (3%)'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map(l => (
                <tr key={l.id} className="hover:bg-gray-50/50">
                  <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{l.date}</td>
                  <td className="px-4 py-2 font-mono text-xs font-semibold text-gray-900">{l.si_number}</td>
                  <td className="px-4 py-2 text-xs text-gray-900 max-w-[150px] truncate">{l.customer_name_snapshot}</td>
                  <td className="px-4 py-2 font-mono text-xs text-gray-500">{l.customer_tin_snapshot || '—'}</td>
                  <td className="px-4 py-2 text-xs text-gray-700 max-w-[180px] truncate">{l.description}</td>
                  <td className="px-4 py-2">
                    <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase ${l.vat_classification === 'exempt' ? 'bg-gray-100 text-gray-600' : 'bg-blue-50 text-blue-700'}`}>
                      {l.vat_classification === 'exempt' ? 'Exempt' : 'Zero-Rated'}
                    </span>
                  </td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-900">{fmt(l.net_amount)}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-blue-700">{fmt(l.net_amount * PT_RATE)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t-2 border-gray-300 bg-gray-50">
              <tr>
                <td colSpan={6} className="px-4 py-2.5 text-xs font-semibold text-gray-700">TOTAL — {lines.length} line{lines.length !== 1 ? 's' : ''}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(totalBase)}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-blue-700">{fmt(totalPT)}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
