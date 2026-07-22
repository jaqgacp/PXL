import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type RegTab = 'si' | 'or' | 'cm' | 'dm'

type SIRow = { si_number: string; date: string; customer_name_snapshot: string; customer_tin_snapshot: string; project_code: string | null; project_name: string | null; location_code: string | null; location_name: string | null; functional_entity_code: string | null; functional_entity_name: string | null; total_taxable_amount: number; total_zero_rated_amount: number; total_exempt_amount: number; total_vat_amount: number; total_amount: number; status: string; memo: string | null }
type ORRow = { receipt_number: string; receipt_date: string; customer_name_snapshot: string; customer_tin_snapshot: string; total_amount: number; total_cwt: number; remarks: string | null; status: string; reference_number: string | null }
type CMRow = { cm_number: string; cm_date: string; customer_name_snapshot: string; customer_tin_snapshot: string; total_net_amount: number; total_vat_amount: number; total_amount: number; remarks: string | null; status: string; reason_description: string | null }
type DMRow = { dm_number: string; dm_date: string; customer_name_snapshot: string; customer_tin_snapshot: string; total_net_amount: number; total_vat_amount: number; total_amount: number; remarks: string | null; status: string; reason_description: string | null }

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); d.setDate(1); return d.toISOString().split('T')[0] }

const statusBadge: Record<string, string> = {
  posted: 'posted', draft: 'draft', approved: 'approved', applied: 'posted',
  cancelled: 'error', bounced: 'warning', paid: 'posted', partial: 'warning',
}

const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'

export default function SalesRegistersPage() {
  const { companyId } = useAppCtx()
  const [tab, setTab] = useState<RegTab>('si')
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(today())
  const [loading, setLoading] = useState(false)

  const [siRows, setSIRows] = useState<SIRow[]>([])
  const [orRows, setORRows] = useState<ORRow[]>([])
  const [cmRows, setCMRows] = useState<CMRow[]>([])
  const [dmRows, setDMRows] = useState<DMRow[]>([])

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    if (tab === 'si') {
      const { data } = await supabase.from('vw_sales_invoice_register')
        .select('si_number,date,customer_name_snapshot,customer_tin_snapshot,project_code,project_name,location_code,location_name,functional_entity_code,functional_entity_name,total_taxable_amount,total_zero_rated_amount,total_exempt_amount,total_vat_amount,total_amount,status,memo')
        .eq('company_id', companyId).gte('date', dateFrom).lte('date', dateTo)
        .order('date').order('si_number')
      setSIRows(data as SIRow[] || [])
    } else if (tab === 'or') {
      const { data } = await supabase.from('vw_receipt_register')
        .select('receipt_number,receipt_date,customer_name_snapshot,customer_tin_snapshot,total_amount,total_cwt,remarks,status,reference_number')
        .eq('company_id', companyId).gte('receipt_date', dateFrom).lte('receipt_date', dateTo)
        .order('receipt_date').order('receipt_number')
      setORRows(data as ORRow[] || [])
    } else if (tab === 'cm') {
      const { data } = await supabase.from('vw_credit_memo_register')
        .select('cm_number,cm_date,customer_name_snapshot,customer_tin_snapshot,total_net_amount,total_vat_amount,total_amount,remarks,status,reason_description')
        .eq('company_id', companyId).gte('cm_date', dateFrom).lte('cm_date', dateTo)
        .order('cm_date').order('cm_number')
      setCMRows(data as CMRow[] || [])
    } else {
      const { data } = await supabase.from('vw_debit_memo_register')
        .select('dm_number,dm_date,customer_name_snapshot,customer_tin_snapshot,total_net_amount,total_vat_amount,total_amount,remarks,status,reason_description')
        .eq('company_id', companyId).gte('dm_date', dateFrom).lte('dm_date', dateTo)
        .order('dm_date').order('dm_number')
      setDMRows(data as DMRow[] || [])
    }

    setLoading(false)
  }, [companyId, tab, dateFrom, dateTo])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const TAB_LABELS: Record<RegTab, string> = {
    si: 'Sales Invoice Register', or: 'Receipt Register',
    cm: 'Credit Memo Register', dm: 'Debit Memo Register',
  }

  return (
    <div>
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        {(['si','or','cm','dm'] as RegTab[]).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${tab === t ? 'bg-gray-900 text-white' : 'text-gray-600 hover:bg-gray-100'}`}>
            {t.toUpperCase()}
          </button>
        ))}
        <span className="text-gray-200">|</span>
        <div className="flex items-center gap-2">
          <label className="text-xs text-gray-500">From</label>
          <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className={inp} />
        </div>
        <div className="flex items-center gap-2">
          <label className="text-xs text-gray-500">To</label>
          <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className={inp} />
        </div>
        <button onClick={load} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">Run</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>

      {/* Sub-header */}
      <div className="bg-gray-50 border-b border-gray-200 px-5 py-1.5">
        <span className="text-xs font-semibold text-gray-500">{TAB_LABELS[tab]} — {dateFrom} to {dateTo}</span>
      </div>

      {/* Tables */}
      {loading ? (
        <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
      ) : (
        <>
          {/* SI Register */}
          {tab === 'si' && (siRows.length === 0 ? (
            <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No invoices in this period</p></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date','SI Number','Customer Name','TIN','Project','Location','Functional Entity','Vatable','Zero-Rated','Exempt','Output VAT','Total','Status'].map(h => (
                      <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Vatable','Zero-Rated','Exempt','Output VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {siRows.map((r, i) => (
                    <tr key={i} className={`hover:bg-gray-50/50 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.date}</td>
                      <td className={`px-4 py-2 font-mono text-xs font-semibold whitespace-nowrap ${r.status === 'cancelled' ? 'line-through text-gray-400' : 'text-gray-900'}`}>{r.si_number}</td>
                      <td className="px-4 py-2 text-xs text-gray-900 max-w-[160px] truncate">{r.customer_name_snapshot}</td>
                      <td className="px-4 py-2 font-mono text-xs text-gray-500">{r.customer_tin_snapshot || '—'}</td>
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.project_code ? `${r.project_code} · ${r.project_name}` : '—'}</td>
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.location_code ? `${r.location_code} · ${r.location_name}` : '—'}</td>
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.functional_entity_code ? `${r.functional_entity_code} · ${r.functional_entity_name}` : '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums">{r.total_taxable_amount ? fmt(Number(r.total_taxable_amount)) : '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{r.total_zero_rated_amount ? fmt(Number(r.total_zero_rated_amount)) : '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{r.total_exempt_amount ? fmt(Number(r.total_exempt_amount)) : '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-blue-700">{r.total_vat_amount ? fmt(Number(r.total_vat_amount)) : '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(r.total_amount))}</td>
                      <td className="px-4 py-2"><StatusBadge status={statusBadge[r.status] || 'draft'} label={r.status === 'cancelled' ? 'Void' : r.status.charAt(0).toUpperCase() + r.status.slice(1)} /></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td colSpan={7} className="px-4 py-2.5 text-xs font-semibold text-gray-700">{siRows.filter(r => r.status === 'posted').length} posted / {siRows.filter(r => r.status === 'cancelled').length} voided</td>
                    {['total_taxable_amount','total_zero_rated_amount','total_exempt_amount','total_vat_amount','total_amount'].map(field => {
                      const total = siRows.filter(r => r.status === 'posted').reduce((s, r) => s + Number(r[field as keyof SIRow] || 0), 0)
                      return <td key={field} className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold ${field === 'total_vat_amount' ? 'text-blue-700' : 'text-gray-900'}`}>{fmt(total)}</td>
                    })}
                    <td />
                  </tr>
                </tfoot>
              </table>
            </div>
          ))}

          {/* OR Register */}
          {tab === 'or' && (orRows.length === 0 ? (
            <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No receipts in this period</p></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date','OR Number','Customer Name','TIN','Reference','Total Amount','CWT','Status'].map(h => (
                      <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Total Amount','CWT'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {orRows.map((r, i) => (
                    <tr key={i} className={`hover:bg-gray-50/50 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.receipt_date}</td>
                      <td className={`px-4 py-2 font-mono text-xs font-semibold whitespace-nowrap ${r.status === 'bounced' ? 'text-amber-700' : r.status === 'cancelled' ? 'line-through text-gray-400' : 'text-gray-900'}`}>{r.receipt_number}</td>
                      <td className="px-4 py-2 text-xs text-gray-900 max-w-[160px] truncate">{r.customer_name_snapshot}</td>
                      <td className="px-4 py-2 font-mono text-xs text-gray-500">{r.customer_tin_snapshot || '—'}</td>
                      <td className="px-4 py-2 text-xs text-gray-400">{r.reference_number || '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(r.total_amount))}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{r.total_cwt ? fmt(Number(r.total_cwt)) : '—'}</td>
                      <td className="px-4 py-2"><StatusBadge status={statusBadge[r.status] || 'draft'} label={r.status.charAt(0).toUpperCase() + r.status.slice(1)} /></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-700">{orRows.filter(r => r.status === 'posted').length} posted</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(orRows.filter(r => r.status === 'posted').reduce((s, r) => s + Number(r.total_amount), 0))}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-500">{fmt(orRows.filter(r => r.status === 'posted').reduce((s, r) => s + Number(r.total_cwt), 0))}</td>
                    <td />
                  </tr>
                </tfoot>
              </table>
            </div>
          ))}

          {/* CM Register */}
          {tab === 'cm' && (cmRows.length === 0 ? (
            <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No credit memos in this period</p></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date','CM Number','Customer Name','TIN','Reason','Net Amount','VAT','Total','Status'].map(h => (
                      <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Net Amount','VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {cmRows.map((r, i) => (
                    <tr key={i} className="hover:bg-gray-50/50">
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.cm_date}</td>
                      <td className="px-4 py-2 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">{r.cm_number}</td>
                      <td className="px-4 py-2 text-xs text-gray-900 max-w-[160px] truncate">{r.customer_name_snapshot}</td>
                      <td className="px-4 py-2 font-mono text-xs text-gray-500">{r.customer_tin_snapshot || '—'}</td>
                      <td className="px-4 py-2 text-xs text-gray-500 max-w-[160px] truncate">{r.reason_description || '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-700">{fmt(Number(r.total_net_amount))}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{fmt(Number(r.total_vat_amount))}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(r.total_amount))}</td>
                      <td className="px-4 py-2"><StatusBadge status={statusBadge[r.status] || 'draft'} label={r.status.charAt(0).toUpperCase() + r.status.slice(1)} /></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-700">{cmRows.length} record{cmRows.length !== 1 ? 's' : ''}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(cmRows.reduce((s, r) => s + Number(r.total_net_amount), 0))}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-500">{fmt(cmRows.reduce((s, r) => s + Number(r.total_vat_amount), 0))}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(cmRows.reduce((s, r) => s + Number(r.total_amount), 0))}</td>
                    <td />
                  </tr>
                </tfoot>
              </table>
            </div>
          ))}

          {/* DM Register */}
          {tab === 'dm' && (dmRows.length === 0 ? (
            <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No debit memos in this period</p></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date','DM Number','Customer Name','TIN','Reason','Net Amount','VAT','Total','Status'].map(h => (
                      <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Net Amount','VAT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {dmRows.map((r, i) => (
                    <tr key={i} className="hover:bg-gray-50/50">
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.dm_date}</td>
                      <td className="px-4 py-2 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">{r.dm_number}</td>
                      <td className="px-4 py-2 text-xs text-gray-900 max-w-[160px] truncate">{r.customer_name_snapshot}</td>
                      <td className="px-4 py-2 font-mono text-xs text-gray-500">{r.customer_tin_snapshot || '—'}</td>
                      <td className="px-4 py-2 text-xs text-gray-500 max-w-[160px] truncate">{r.reason_description || '—'}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-700">{fmt(Number(r.total_net_amount))}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{fmt(Number(r.total_vat_amount))}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(r.total_amount))}</td>
                      <td className="px-4 py-2"><StatusBadge status={statusBadge[r.status] || 'draft'} label={r.status.charAt(0).toUpperCase() + r.status.slice(1)} /></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-700">{dmRows.length} record{dmRows.length !== 1 ? 's' : ''}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(dmRows.reduce((s, r) => s + Number(r.total_net_amount), 0))}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-500">{fmt(dmRows.reduce((s, r) => s + Number(r.total_vat_amount), 0))}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(dmRows.reduce((s, r) => s + Number(r.total_amount), 0))}</td>
                    <td />
                  </tr>
                </tfoot>
              </table>
            </div>
          ))}
        </>
      )}
    </div>
  )
}
