import { useState, useEffect, useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────
type InvoiceRow = {
  id: string; si_number: string; date: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_vat_amount: number; total_amount: number
  status: string
}

type CMAdjRow = {
  cm_number: string; cm_date: string; customer_name_snapshot: string
  customer_tin_snapshot: string
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_vat_amount: number; total_amount: number
}

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function SalesTaxReviewPage() {
  const { companyId } = useAppCtx()
  const [searchParams] = useSearchParams()

  const currentDate = new Date()
  const initialMonth = Number(searchParams.get('month'))
  const initialYear = Number(searchParams.get('year'))
  const sourceId = searchParams.get('sourceId') || ''
  const [selMonth, setSelMonth] = useState(initialMonth >= 1 && initialMonth <= 12 ? initialMonth - 1 : currentDate.getMonth())
  const [selYear, setSelYear] = useState(initialYear >= currentDate.getFullYear() - 10 && initialYear <= currentDate.getFullYear() + 10 ? initialYear : currentDate.getFullYear())
  const [includeVoid, setIncludeVoid] = useState(false)
  const [loading, setLoading] = useState(false)

  const [invoices, setInvoices] = useState<InvoiceRow[]>([])
  const [cmAdjs, setCMAdjs] = useState<CMAdjRow[]>([])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true); setInvoices([]); setCMAdjs([])

    const startDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-01`
    const endDay = new Date(selYear, selMonth + 1, 0).getDate()
    const endDate = `${selYear}-${String(selMonth + 1).padStart(2, '0')}-${endDay}`

    const statuses = includeVoid ? ['posted', 'cancelled'] : ['posted']

    let invoiceQuery = supabase.from('sales_invoices')
      .select('id,si_number,date,customer_name_snapshot,customer_tin_snapshot,total_taxable_amount,total_zero_rated_amount,total_exempt_amount,total_vat_amount,total_amount,status')
      .eq('company_id', companyId).in('status', statuses)
    invoiceQuery = sourceId
      ? invoiceQuery.eq('id', sourceId)
      : invoiceQuery.gte('date', startDate).lte('date', endDate)
    let creditMemoQuery = supabase.from('credit_memos')
      .select('cm_number,cm_date,customer_name_snapshot,customer_tin_snapshot,total_taxable_amount,total_zero_rated_amount,total_exempt_amount,total_vat_amount,total_amount')
      .eq('company_id', companyId).eq('status', 'applied')
    creditMemoQuery = sourceId
      ? creditMemoQuery.eq('invoice_id', sourceId)
      : creditMemoQuery.gte('cm_date', startDate).lte('cm_date', endDate)

    const [{ data: sis }, { data: cms }] = await Promise.all([
      invoiceQuery.order('date').order('si_number'),
      creditMemoQuery.order('cm_date'),
    ])

    setInvoices(sis as InvoiceRow[] || [])
    setCMAdjs(cms as CMAdjRow[] || [])
    setLoading(false)
  }, [companyId, selMonth, selYear, includeVoid, sourceId])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  // ── Summary computations ───────────────────────────────────
  const posted = invoices.filter(i => i.status === 'posted')
  const totalVatable   = posted.reduce((s, i) => s + Number(i.total_taxable_amount), 0)
  const totalZeroRated = posted.reduce((s, i) => s + Number(i.total_zero_rated_amount), 0)
  const totalExempt    = posted.reduce((s, i) => s + Number(i.total_exempt_amount), 0)
  const totalOutputVAT = posted.reduce((s, i) => s + Number(i.total_vat_amount), 0)

  const cmVatable   = cmAdjs.reduce((s, c) => s + Number(c.total_taxable_amount), 0)
  const cmZeroRated = cmAdjs.reduce((s, c) => s + Number(c.total_zero_rated_amount), 0)
  const cmExempt    = cmAdjs.reduce((s, c) => s + Number(c.total_exempt_amount), 0)
  const cmOutputVAT = cmAdjs.reduce((s, c) => s + Number(c.total_vat_amount), 0)

  const netVatable   = totalVatable - cmVatable
  const netZeroRated = totalZeroRated - cmZeroRated
  const netExempt    = totalExempt - cmExempt
  const netOutputVAT = totalOutputVAT - cmOutputVAT

  const yearRange = Array.from({ length: 5 }, (_, i) => currentDate.getFullYear() - 2 + i)

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
        <label className="flex items-center gap-1.5 text-xs text-gray-600 cursor-pointer">
          <input type="checkbox" checked={includeVoid} onChange={e => setIncludeVoid(e.target.checked)} className="h-3.5 w-3.5" />
          Include voided invoices
        </label>
        <button onClick={run} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">Run</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
        {cmAdjs.length > 0 && <span className="text-xs text-amber-600 ml-auto">{cmAdjs.length} Credit Memo adjustment{cmAdjs.length > 1 ? 's' : ''} applied</span>}
      </div>

      {/* KPI Strip */}
      <div className="bg-white border-b border-gray-200 grid grid-cols-2 md:grid-cols-4 divide-x divide-gray-200">
        {[
          { label: 'Total Vatable Sales', value: netVatable, note: cmVatable > 0 ? `Less CM: ${fmt(cmVatable)}` : undefined },
          { label: 'Zero-Rated Sales', value: netZeroRated, note: cmZeroRated > 0 ? `Less CM: ${fmt(cmZeroRated)}` : undefined },
          { label: 'Exempt Sales', value: netExempt, note: cmExempt > 0 ? `Less CM: ${fmt(cmExempt)}` : undefined },
          { label: 'Net Output VAT', value: netOutputVAT, note: cmOutputVAT > 0 ? `Less CM: ${fmt(cmOutputVAT)}` : undefined, accent: true },
        ].map(kpi => (
          <div key={kpi.label} className="px-5 py-3">
            <div className="text-[11px] font-medium text-gray-400 uppercase tracking-wide">{kpi.label}</div>
            <div className={`text-xl font-mono tabular-nums font-bold mt-0.5 ${kpi.accent ? 'text-blue-700' : 'text-gray-900'}`}>{fmt(kpi.value)}</div>
            {kpi.note && <div className="text-[10px] text-gray-400 mt-0.5">{kpi.note}</div>}
          </div>
        ))}
      </div>

      {/* Detail Table */}
      {loading ? (
        <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
      ) : invoices.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No posted invoices</p>
          <p className="text-xs text-gray-400 mt-1">No Sales Invoices found for {MONTHS[selMonth]} {selYear}.</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Date','SI Number','Customer','TIN','Vatable Sales','Zero-Rated','Exempt','Output VAT','Total','Status'].map(h => (
                  <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Vatable Sales','Zero-Rated','Exempt','Output VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {invoices.map(inv => (
                <tr key={inv.id} className={`hover:bg-gray-50/50 ${inv.status === 'cancelled' ? 'opacity-50' : ''}`}>
                  <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{inv.date}</td>
                  <td className={`px-4 py-2 font-mono text-xs font-semibold whitespace-nowrap ${inv.status === 'cancelled' ? 'line-through text-gray-400' : 'text-gray-900'}`}>{inv.si_number}</td>
                  <td className="px-4 py-2 text-xs text-gray-900 max-w-[160px] truncate">{inv.customer_name_snapshot}</td>
                  <td className="px-4 py-2 font-mono text-xs text-gray-500 whitespace-nowrap">{inv.customer_tin_snapshot || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-700">{inv.total_taxable_amount ? fmt(Number(inv.total_taxable_amount)) : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{inv.total_zero_rated_amount ? fmt(Number(inv.total_zero_rated_amount)) : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{inv.total_exempt_amount ? fmt(Number(inv.total_exempt_amount)) : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-blue-700">{inv.total_vat_amount ? fmt(Number(inv.total_vat_amount)) : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(inv.total_amount))}</td>
                  <td className="px-4 py-2">
                    <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase ${inv.status === 'posted' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
                      {inv.status === 'cancelled' ? 'Void' : 'Posted'}
                    </span>
                  </td>
                </tr>
              ))}
              {/* CM Adjustments */}
              {cmAdjs.map(cm => (
                <tr key={cm.cm_number} className="bg-amber-50/40 hover:bg-amber-50">
                  <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{cm.cm_date}</td>
                  <td className="px-4 py-2 font-mono text-xs font-semibold text-amber-700 whitespace-nowrap">{cm.cm_number}</td>
                  <td className="px-4 py-2 text-xs text-gray-700 max-w-[160px] truncate">{cm.customer_name_snapshot}</td>
                  <td className="px-4 py-2 font-mono text-xs text-gray-500">{cm.customer_tin_snapshot || '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-red-600">{cm.total_taxable_amount ? `(${fmt(Number(cm.total_taxable_amount))})` : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-red-600">{cm.total_zero_rated_amount ? `(${fmt(Number(cm.total_zero_rated_amount))})` : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-red-600">{cm.total_exempt_amount ? `(${fmt(Number(cm.total_exempt_amount))})` : '—'}</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-red-600">({fmt(Number(cm.total_vat_amount))})</td>
                  <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-red-600 font-semibold">({fmt(Number(cm.total_amount))})</td>
                  <td className="px-4 py-2"><span className="inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase bg-amber-50 text-amber-700">CM</span></td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t-2 border-gray-300 bg-gray-50">
              <tr>
                <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-700">NET TOTALS — {invoices.filter(i => i.status === 'posted').length} posted invoice{invoices.filter(i => i.status === 'posted').length !== 1 ? 's' : ''}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(netVatable)}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(netZeroRated)}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(netExempt)}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-blue-700">{fmt(netOutputVAT)}</td>
                <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(posted.reduce((s, i) => s + Number(i.total_amount), 0) - cmAdjs.reduce((s, c) => s + Number(c.total_amount), 0))}</td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
