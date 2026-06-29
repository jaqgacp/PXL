import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { DateCell, StatusBadge } from '@/components/ui/shared'

type RegisterTab = 'vendor-bill' | 'payment' | 'debit-memo' | 'slp'

type VBRow = {
  id: string; bill_number: string; bill_date: string; due_date: string | null
  supplier_name: string; supplier_tin: string | null; invoice_no: string | null
  gross_amount: number; exempt_amount: number; zero_rated_amount: number
  taxable_amount: number; vat_amount: number; ewt_amount: number
  total_amount: number; status: string
}

type PVRow = {
  id: string; voucher_number: string; voucher_date: string
  supplier_name: string; supplier_tin: string | null; reference_number: string | null
  check_number: string | null; check_date: string | null
  total_amount: number; total_ewt: number; status: string
  date_released: string | null; date_cleared: string | null
}

type SDMRow = {
  id: string; memo_number: string; memo_date: string
  supplier_name: string; supplier_tin: string | null
  total_amount: number; status: string
  date_sent: string | null; date_acknowledged: string | null
}

type SLPRow = {
  supplier_id: string; supplier_name: string; supplier_tin: string | null
  period_year: number; period_month: number
  gross_purchases: number; exempt_purchases: number
  zero_rated: number; taxable_base: number; input_vat: number
  transaction_count: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const todayStr = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); d.setDate(1); return d.toISOString().split('T')[0] }

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

const VB_STATUS_COLORS: Record<string, string> = { draft: 'draft', approved: 'approved', posted: 'posted', void: 'error', cancelled: 'error' }
const PV_STATUS_COLORS: Record<string, string> = { draft: 'draft', posted: 'approved', released: 'warning', cleared: 'posted', stale: 'error', cancelled: 'error' }
const SDM_STATUS_COLORS: Record<string, string> = { draft: 'draft', sent: 'warning', acknowledged: 'posted', cancelled: 'error' }

export default function PurchaseRegistersPage() {
  const { companyId } = useAppCtx()
  const [tab, setTab] = useState<RegisterTab>('vendor-bill')
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo, setDateTo] = useState(todayStr())
  const [search, setSearch] = useState('')
  const [vbRows, setVbRows] = useState<VBRow[]>([])
  const [pvRows, setPvRows] = useState<PVRow[]>([])
  const [sdmRows, setSdmRows] = useState<SDMRow[]>([])
  const [slpRows, setSlpRows] = useState<SLPRow[]>([])
  const [loading, setLoading] = useState(false)

  const now = new Date()
  const [slpYear, setSlpYear] = useState(now.getFullYear())
  const [slpMonth, setSlpMonth] = useState(now.getMonth() + 1)

  const loadVB = useCallback(async () => {
    if (!companyId) return
    let q = supabase.from('vw_vendor_bill_register').select('*').eq('company_id', companyId).gte('bill_date', dateFrom).lte('bill_date', dateTo).order('bill_date', { ascending: false })
    if (search) q = q.or(`bill_number.ilike.%${search}%,supplier_name.ilike.%${search}%,invoice_no.ilike.%${search}%`)
    const { data } = await q
    setVbRows(data as VBRow[] || [])
  }, [companyId, dateFrom, dateTo, search])

  const loadPV = useCallback(async () => {
    if (!companyId) return
    let q = supabase.from('vw_payment_register').select('*').eq('company_id', companyId).gte('voucher_date', dateFrom).lte('voucher_date', dateTo).order('voucher_date', { ascending: false })
    if (search) q = q.or(`voucher_number.ilike.%${search}%,supplier_name.ilike.%${search}%,check_number.ilike.%${search}%`)
    const { data } = await q
    setPvRows(data as PVRow[] || [])
  }, [companyId, dateFrom, dateTo, search])

  const loadSDM = useCallback(async () => {
    if (!companyId) return
    let q = supabase.from('vw_sdm_register').select('*').eq('company_id', companyId).gte('memo_date', dateFrom).lte('memo_date', dateTo).order('memo_date', { ascending: false })
    if (search) q = q.or(`memo_number.ilike.%${search}%,supplier_name.ilike.%${search}%`)
    const { data } = await q
    setSdmRows(data as SDMRow[] || [])
  }, [companyId, dateFrom, dateTo, search])

  const loadSLP = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('vw_slp_export').select('*').eq('company_id', companyId).eq('period_year', slpYear).eq('period_month', slpMonth).order('supplier_name')
    setSlpRows(data as SLPRow[] || [])
  }, [companyId, slpYear, slpMonth])

  useEffect(() => {
    if (!companyId) return
    setLoading(true)
    const p = tab === 'vendor-bill' ? loadVB() : tab === 'payment' ? loadPV() : tab === 'debit-memo' ? loadSDM() : loadSLP()
    p.then(() => setLoading(false))
  }, [tab, companyId, loadVB, loadPV, loadSDM, loadSLP])

  const exportCSV = () => {
    let headers: string[] = []
    let rows: any[][] = []
    if (tab === 'vendor-bill') {
      headers = ['Bill Date','Bill #','Supplier','TIN','Invoice #','Gross','Exempt','Zero-Rated','Taxable','VAT','EWT','Total','Status']
      rows = vbRows.map(r => [r.bill_date, r.bill_number, r.supplier_name, r.supplier_tin || '', r.invoice_no || '', r.gross_amount, r.exempt_amount, r.zero_rated_amount, r.taxable_amount, r.vat_amount, r.ewt_amount, r.total_amount, r.status])
    } else if (tab === 'payment') {
      headers = ['PV Date','PV #','Supplier','TIN','Check #','Check Date','Amount','EWT','Status','Released','Cleared']
      rows = pvRows.map(r => [r.voucher_date, r.voucher_number, r.supplier_name, r.supplier_tin || '', r.check_number || '', r.check_date || '', r.total_amount, r.total_ewt, r.status, r.date_released || '', r.date_cleared || ''])
    } else if (tab === 'debit-memo') {
      headers = ['Memo Date','Memo #','Supplier','TIN','Amount','Status','Sent','Acknowledged']
      rows = sdmRows.map(r => [r.memo_date, r.memo_number, r.supplier_name, r.supplier_tin || '', r.total_amount, r.status, r.date_sent || '', r.date_acknowledged || ''])
    } else {
      headers = ['Supplier','TIN','Year','Month','Gross Purchases','Exempt','Zero-Rated','Taxable Base','Input VAT','Count']
      rows = slpRows.map(r => [r.supplier_name, r.supplier_tin || '', r.period_year, r.period_month, r.gross_purchases, r.exempt_purchases, r.zero_rated, r.taxable_base, r.input_vat, r.transaction_count])
    }
    const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }))
    a.download = `${tab}-register-${dateFrom}-${dateTo}.csv`
    a.click()
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900'
  const TABS: { key: RegisterTab; label: string }[] = [
    { key: 'vendor-bill', label: 'Vendor Bill Register' },
    { key: 'payment', label: 'Payment Register' },
    { key: 'debit-memo', label: 'Debit Memo Register' },
    { key: 'slp', label: 'SLP Export' },
  ]

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex gap-4 border-b border-gray-200">
          {TABS.map(t => (
            <button key={t.key} onClick={() => setTab(t.key)} className={`pb-2 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${tab === t.key ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>{t.label}</button>
          ))}
        </div>
        <button onClick={exportCSV} className="ml-4 px-3 py-1.5 text-xs border border-gray-300 rounded-md hover:bg-gray-50">Export CSV</button>
      </div>

      <div className="flex gap-3 flex-wrap">
        {tab !== 'slp' ? (
          <>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">From</label><input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className={inp} /></div>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">To</label><input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className={inp} /></div>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">Search</label><input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Number, supplier…" className={inp + ' w-52'} /></div>
          </>
        ) : (
          <>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">Year</label><select value={slpYear} onChange={e => setSlpYear(+e.target.value)} className={inp}>{[now.getFullYear() - 1, now.getFullYear()].map(y => <option key={y} value={y}>{y}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">Month</label><select value={slpMonth} onChange={e => setSlpMonth(+e.target.value)} className={inp}>{MONTHS.map((m, i) => <option key={i + 1} value={i + 1}>{m}</option>)}</select></div>
          </>
        )}
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : (
          <>
            {tab === 'vendor-bill' && (
              vbRows.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No vendor bills in this period.</div> : (
                <table className="w-full text-xs">
                  <thead className="bg-gray-50 border-b border-gray-200">
                    <tr>{['Date','Bill #','Supplier','TIN','Invoice #','Gross','Exempt','Zero-Rtd','Taxable','VAT','EWT','Total','Status'].map(h => (
                      <th key={h} className={`px-2 py-2 font-medium text-gray-500 ${['Gross','Exempt','Zero-Rtd','Taxable','VAT','EWT','Total'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}</tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {vbRows.map(r => (
                      <tr key={r.id} className="hover:bg-gray-50">
                        <td className="px-2 py-1.5"><DateCell date={r.bill_date} /></td>
                        <td className="px-2 py-1.5 font-mono font-medium text-gray-900">{r.bill_number}</td>
                        <td className="px-2 py-1.5 max-w-[120px] truncate text-gray-700">{r.supplier_name}</td>
                        <td className="px-2 py-1.5 font-mono text-gray-500">{r.supplier_tin || '—'}</td>
                        <td className="px-2 py-1.5 font-mono text-gray-500">{r.invoice_no || '—'}</td>
                        <td className="px-2 py-1.5 text-right font-mono">{fmt(r.gross_amount)}</td>
                        <td className="px-2 py-1.5 text-right font-mono text-gray-400">{r.exempt_amount > 0 ? fmt(r.exempt_amount) : '—'}</td>
                        <td className="px-2 py-1.5 text-right font-mono text-blue-600">{r.zero_rated_amount > 0 ? fmt(r.zero_rated_amount) : '—'}</td>
                        <td className="px-2 py-1.5 text-right font-mono">{fmt(r.taxable_amount)}</td>
                        <td className="px-2 py-1.5 text-right font-mono text-green-600">{r.vat_amount > 0 ? fmt(r.vat_amount) : '—'}</td>
                        <td className="px-2 py-1.5 text-right font-mono text-red-600">{r.ewt_amount > 0 ? fmt(r.ewt_amount) : '—'}</td>
                        <td className="px-2 py-1.5 text-right font-mono font-semibold">{fmt(r.total_amount)}</td>
                        <td className="px-2 py-1.5"><StatusBadge status={VB_STATUS_COLORS[r.status] || 'draft'} label={r.status} /></td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot className="bg-gray-50 border-t-2 border-gray-300 text-xs font-semibold">
                    <tr>
                      <td colSpan={5} className="px-2 py-2 text-right text-gray-600">{vbRows.length} records</td>
                      {(['gross_amount','exempt_amount','zero_rated_amount','taxable_amount','vat_amount','ewt_amount','total_amount'] as const).map(k => (
                        <td key={k} className="px-2 py-2 text-right font-mono">{fmt(vbRows.reduce((s, r) => s + (r[k] || 0), 0))}</td>
                      ))}
                      <td />
                    </tr>
                  </tfoot>
                </table>
              )
            )}
            {tab === 'payment' && (
              pvRows.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No payment vouchers in this period.</div> : (
                <table className="w-full text-xs">
                  <thead className="bg-gray-50 border-b border-gray-200">
                    <tr>{['PV Date','PV #','Supplier','TIN','Check #','Check Date','Amount','EWT','Status','Released','Cleared'].map(h => (
                      <th key={h} className={`px-2 py-2 font-medium text-gray-500 ${['Amount','EWT'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}</tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {pvRows.map(r => (
                      <tr key={r.id} className="hover:bg-gray-50">
                        <td className="px-2 py-1.5"><DateCell date={r.voucher_date} /></td>
                        <td className="px-2 py-1.5 font-mono font-medium text-gray-900">{r.voucher_number}</td>
                        <td className="px-2 py-1.5 max-w-[120px] truncate text-gray-700">{r.supplier_name}</td>
                        <td className="px-2 py-1.5 font-mono text-gray-500">{r.supplier_tin || '—'}</td>
                        <td className="px-2 py-1.5 font-mono text-gray-500">{r.check_number || '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500">{r.check_date ? <DateCell date={r.check_date} /> : '—'}</td>
                        <td className="px-2 py-1.5 text-right font-mono font-semibold">{fmt(r.total_amount)}</td>
                        <td className="px-2 py-1.5 text-right font-mono text-red-600">{r.total_ewt > 0 ? fmt(r.total_ewt) : '—'}</td>
                        <td className="px-2 py-1.5"><StatusBadge status={PV_STATUS_COLORS[r.status] || 'draft'} label={r.status} /></td>
                        <td className="px-2 py-1.5 text-gray-500">{r.date_released ? <DateCell date={r.date_released} /> : '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500">{r.date_cleared ? <DateCell date={r.date_cleared} /> : '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot className="bg-gray-50 border-t-2 border-gray-300 text-xs font-semibold">
                    <tr>
                      <td colSpan={6} className="px-2 py-2 text-right text-gray-600">{pvRows.length} records</td>
                      <td className="px-2 py-2 text-right font-mono">{fmt(pvRows.reduce((s, r) => s + r.total_amount, 0))}</td>
                      <td className="px-2 py-2 text-right font-mono text-red-600">{fmt(pvRows.reduce((s, r) => s + r.total_ewt, 0))}</td>
                      <td colSpan={3} />
                    </tr>
                  </tfoot>
                </table>
              )
            )}
            {tab === 'debit-memo' && (
              sdmRows.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No debit memos in this period.</div> : (
                <table className="w-full text-xs">
                  <thead className="bg-gray-50 border-b border-gray-200">
                    <tr>{['Memo Date','Memo #','Supplier','TIN','Amount','Status','Date Sent','Date Acknowledged'].map(h => (
                      <th key={h} className={`px-3 py-2 font-medium text-gray-500 ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}</tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {sdmRows.map(r => (
                      <tr key={r.id} className="hover:bg-gray-50">
                        <td className="px-3 py-1.5"><DateCell date={r.memo_date} /></td>
                        <td className="px-3 py-1.5 font-mono font-medium text-gray-900">{r.memo_number}</td>
                        <td className="px-3 py-1.5 max-w-[140px] truncate text-gray-700">{r.supplier_name}</td>
                        <td className="px-3 py-1.5 font-mono text-gray-500">{r.supplier_tin || '—'}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold">{fmt(r.total_amount)}</td>
                        <td className="px-3 py-1.5"><StatusBadge status={SDM_STATUS_COLORS[r.status] || 'draft'} label={r.status} /></td>
                        <td className="px-3 py-1.5 text-gray-500">{r.date_sent ? <DateCell date={r.date_sent} /> : '—'}</td>
                        <td className="px-3 py-1.5 text-gray-500">{r.date_acknowledged ? <DateCell date={r.date_acknowledged} /> : '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )
            )}
            {tab === 'slp' && (
              slpRows.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No SLP data for {MONTHS[slpMonth - 1]} {slpYear}.</div> : (
                <table className="w-full text-xs">
                  <thead className="bg-gray-50 border-b border-gray-200">
                    <tr>{['Supplier','TIN','Gross Purchases','Exempt','Zero-Rated','Taxable Base','Input VAT','Count'].map(h => (
                      <th key={h} className={`px-3 py-2 font-medium text-gray-500 ${['Gross Purchases','Exempt','Zero-Rated','Taxable Base','Input VAT','Count'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}</tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {slpRows.map((r, i) => (
                      <tr key={i} className="hover:bg-gray-50">
                        <td className="px-3 py-1.5 text-gray-700">{r.supplier_name}</td>
                        <td className="px-3 py-1.5 font-mono text-gray-500">{r.supplier_tin || '—'}</td>
                        <td className="px-3 py-1.5 text-right font-mono">{fmt(r.gross_purchases)}</td>
                        <td className="px-3 py-1.5 text-right font-mono text-gray-400">{r.exempt_purchases > 0 ? fmt(r.exempt_purchases) : '—'}</td>
                        <td className="px-3 py-1.5 text-right font-mono text-blue-600">{r.zero_rated > 0 ? fmt(r.zero_rated) : '—'}</td>
                        <td className="px-3 py-1.5 text-right font-mono">{fmt(r.taxable_base)}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-medium text-green-700">{fmt(r.input_vat)}</td>
                        <td className="px-3 py-1.5 text-right font-mono text-gray-500">{r.transaction_count}</td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot className="bg-gray-50 border-t-2 border-gray-300 text-xs font-semibold">
                    <tr>
                      <td colSpan={2} className="px-3 py-2 text-right text-gray-600">{slpRows.length} suppliers</td>
                      {(['gross_purchases','exempt_purchases','zero_rated','taxable_base','input_vat'] as const).map(k => (
                        <td key={k} className="px-3 py-2 text-right font-mono">{fmt(slpRows.reduce((s, r) => s + r[k], 0))}</td>
                      ))}
                      <td className="px-3 py-2 text-right font-mono text-gray-500">{slpRows.reduce((s, r) => s + r.transaction_count, 0)}</td>
                    </tr>
                  </tfoot>
                </table>
              )
            )}
          </>
        )}
      </div>
    </div>
  )
}
