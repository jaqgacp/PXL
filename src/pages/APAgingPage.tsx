import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'


type Tab = 'aging' | 'ledger'

type SupplierRef = { id: string; registered_name: string }

type AgingBill = {
  id: string; bill_number: string; bill_date: string; due_date: string | null
  supplier_id: string; supplier_name: string; total_amount: number; balance_due: number
  days_overdue: number
}

type AgingRow = {
  supplier_id: string; supplier_name: string
  current_bal: number; days_1_30: number; days_31_60: number
  days_61_90: number; over_90: number; total_ap: number
}

type LedgerRow = {
  transaction_date: string; document_type: string; document_number: string
  external_ref: string | null; description: string | null
  debit_amount: number; credit_amount: number; running_balance: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); d.setDate(1); return d.toISOString().split('T')[0] }

const DOC_LABELS: Record<string, string> = {
  vendor_bill: 'Vendor Bill', payment_voucher: 'Payment Voucher', vendor_credit: 'Vendor Credit',
}

const toAgingBills = async (
  companyId: string,
  asOfDate: string,
  supplierId?: string
): Promise<AgingBill[]> => {
  const { data } = await supabase.rpc('fn_ap_aging_asof', {
    p_company_id: companyId,
    p_as_of: asOfDate,
    p_supplier_id: supplierId || null,
  })

  return ((data as any[]) || []).map(r => ({
    id: r.bill_id,
    bill_number: r.bill_number,
    bill_date: r.bill_date,
    due_date: r.due_date,
    supplier_id: r.supplier_id,
    supplier_name: r.supplier_name,
    total_amount: Number(r.original_amount),
    balance_due: Number(r.balance_due),
    days_overdue: r.days_overdue,
  }))
}

export default function APAgingPage() {
  const { companyId } = useAppCtx()
  const [tab, setTab] = useState<Tab>('aging')
  const [asOfDate, setAsOfDate] = useState(today())
  const [agingSupplier, setAgingSupplier] = useState('')
  const [agingRows, setAgingRows] = useState<AgingRow[]>([])
  const [agingLoading, setAgingLoading] = useState(false)
  const [expandedSupplier, setExpandedSupplier] = useState<string | null>(null)
  const [supplierBills, setSupplierBills] = useState<AgingBill[]>([])
  const [ledgerSupplier, setLedgerSupplier] = useState('')
  const [ledgerStart, setLedgerStart] = useState(firstOfMonth())
  const [ledgerEnd, setLedgerEnd] = useState(today())
  const [ledgerRows, setLedgerRows] = useState<LedgerRow[]>([])
  const [ledgerLoading, setLedgerLoading] = useState(false)
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])

  useEffect(() => {
    if (!companyId) return
    supabase.from('suppliers').select('id,registered_name').eq('company_id', companyId).eq('is_active', true).order('registered_name')
      .then(({ data }) => setSuppliers(data as SupplierRef[] || []))
  }, [companyId])

  const runAging = useCallback(async () => {
    if (!companyId) return
    setAgingLoading(true); setAgingRows([]); setExpandedSupplier(null); setSupplierBills([])
    const asOf = new Date(asOfDate)

    const bills = await toAgingBills(companyId, asOfDate, agingSupplier || undefined)
    if (bills.length === 0) { setAgingLoading(false); return }

    const grouped: Record<string, AgingRow> = {}
    for (const b of bills) {
      const bal = b.balance_due || 0
      if (bal <= 0) continue
      const dueDate = b.due_date ? new Date(b.due_date) : null
      const daysOverdue = dueDate ? Math.floor((asOf.getTime() - dueDate.getTime()) / 86400000) : 0
      const sid = b.supplier_id
      if (!grouped[sid]) grouped[sid] = { supplier_id: sid, supplier_name: b.supplier_name, current_bal: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total_ap: 0 }
      grouped[sid].total_ap += bal
      if (daysOverdue <= 0) grouped[sid].current_bal += bal
      else if (daysOverdue <= 30) grouped[sid].days_1_30 += bal
      else if (daysOverdue <= 60) grouped[sid].days_31_60 += bal
      else if (daysOverdue <= 90) grouped[sid].days_61_90 += bal
      else grouped[sid].over_90 += bal
    }
    setAgingRows(Object.values(grouped).sort((a, b) => b.total_ap - a.total_ap))
    setAgingLoading(false)
  }, [companyId, asOfDate, agingSupplier])

  useEffect(() => { if (companyId) runAging() }, [runAging, companyId])

  const expandSupplier = async (sid: string) => {
    if (expandedSupplier === sid) { setExpandedSupplier(null); return }
    setExpandedSupplier(sid)
    const asOf = new Date(asOfDate)
    const bills = await toAgingBills(companyId!, asOfDate, sid)
    setSupplierBills(bills.map(b => ({
      ...b,
      days_overdue: b.due_date ? Math.floor((asOf.getTime() - new Date(b.due_date).getTime()) / 86400000) : 0,
    })))
  }

  const runLedger = useCallback(async () => {
    if (!companyId || !ledgerSupplier) { setLedgerRows([]); return }
    setLedgerLoading(true)
    const { data } = await supabase.from('vw_supplier_ledger').select('*').eq('company_id', companyId).eq('supplier_id', ledgerSupplier).gte('transaction_date', ledgerStart).lte('transaction_date', ledgerEnd).order('transaction_date').order('created_at')
    if (!data) { setLedgerLoading(false); return }
    let balance = 0
    const rows: LedgerRow[] = (data as any[]).map(row => {
      balance = balance + row.credit_amount - row.debit_amount
      return { ...row, running_balance: balance }
    })
    setLedgerRows(rows)
    setLedgerLoading(false)
  }, [companyId, ledgerSupplier, ledgerStart, ledgerEnd])

  useEffect(() => { if (companyId) runLedger() }, [runLedger, companyId])

  const grandTotals = agingRows.reduce((acc, r) => ({ current_bal: acc.current_bal + r.current_bal, days_1_30: acc.days_1_30 + r.days_1_30, days_31_60: acc.days_31_60 + r.days_31_60, days_61_90: acc.days_61_90 + r.days_61_90, over_90: acc.over_90 + r.over_90, total_ap: acc.total_ap + r.total_ap }), { current_bal: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total_ap: 0 })

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900'

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4 border-b border-gray-200 pb-0">
        {(['aging', 'ledger'] as Tab[]).map(t => (
          <button key={t} onClick={() => setTab(t)} className={`pb-2 text-sm font-medium border-b-2 transition-colors ${tab === t ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {t === 'aging' ? 'AP Aging' : 'Supplier Ledger'}
          </button>
        ))}
      </div>

      {tab === 'aging' && (
        <div className="space-y-3">
          <div className="flex gap-3 items-end">
            <div><label className="block text-xs font-medium text-gray-700 mb-1">As of Date</label><input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)} className={inp} /></div>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">Supplier</label>
              <select value={agingSupplier} onChange={e => setAgingSupplier(e.target.value)} className={inp}>
                <option value="">All Suppliers</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}
              </select>
            </div>
            <button onClick={runAging} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">Refresh</button>
          </div>

          {agingLoading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : (
            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    <th className="px-3 py-2 text-left font-medium text-gray-500">Supplier</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">Current</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">1–30 Days</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">31–60 Days</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">61–90 Days</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">&gt; 90 Days</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">Total AP</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {agingRows.length === 0 ? (
                    <tr><td colSpan={7} className="px-3 py-6 text-center text-gray-400">No open payables found.</td></tr>
                  ) : agingRows.map(row => (
                    <>
                      <tr key={row.supplier_id} className="hover:bg-gray-50 cursor-pointer" onClick={() => expandSupplier(row.supplier_id)}>
                        <td className="px-3 py-2 font-medium text-gray-900 flex items-center gap-1">
                          <span className="text-gray-400">{expandedSupplier === row.supplier_id ? '▾' : '▸'}</span> {row.supplier_name}
                        </td>
                        <td className="px-3 py-2 text-right font-mono">{row.current_bal > 0 ? fmt(row.current_bal) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono text-amber-600">{row.days_1_30 > 0 ? fmt(row.days_1_30) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono text-orange-600">{row.days_31_60 > 0 ? fmt(row.days_31_60) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono text-red-600">{row.days_61_90 > 0 ? fmt(row.days_61_90) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono text-red-700 font-semibold">{row.over_90 > 0 ? fmt(row.over_90) : '—'}</td>
                        <td className="px-3 py-2 text-right font-mono font-semibold">{fmt(row.total_ap)}</td>
                      </tr>
                      {expandedSupplier === row.supplier_id && supplierBills.map(b => (
                        <tr key={b.id} className="bg-blue-50">
                          <td className="px-3 py-1.5 pl-8 text-gray-600 font-mono">{b.bill_number}</td>
                          <td className="px-3 py-1.5 text-right font-mono text-gray-500">{b.due_date || b.bill_date}</td>
                          <td colSpan={4} className="px-3 py-1.5 text-xs text-gray-500">{b.days_overdue > 0 ? `${b.days_overdue} days overdue` : 'Current'}</td>
                          <td className="px-3 py-1.5 text-right font-mono text-gray-700">{fmt(b.balance_due)}</td>
                        </tr>
                      ))}
                    </>
                  ))}
                </tbody>
                {agingRows.length > 0 && (
                  <tfoot className="bg-gray-50 border-t-2 border-gray-300 font-semibold">
                    <tr>
                      <td className="px-3 py-2 text-xs text-gray-700">Grand Total</td>
                      <td className="px-3 py-2 text-right font-mono text-xs">{fmt(grandTotals.current_bal)}</td>
                      <td className="px-3 py-2 text-right font-mono text-xs text-amber-600">{fmt(grandTotals.days_1_30)}</td>
                      <td className="px-3 py-2 text-right font-mono text-xs text-orange-600">{fmt(grandTotals.days_31_60)}</td>
                      <td className="px-3 py-2 text-right font-mono text-xs text-red-600">{fmt(grandTotals.days_61_90)}</td>
                      <td className="px-3 py-2 text-right font-mono text-xs text-red-700">{fmt(grandTotals.over_90)}</td>
                      <td className="px-3 py-2 text-right font-mono">{fmt(grandTotals.total_ap)}</td>
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>
          )}
        </div>
      )}

      {tab === 'ledger' && (
        <div className="space-y-3">
          <div className="flex gap-3 items-end flex-wrap">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Supplier *</label>
              <select value={ledgerSupplier} onChange={e => setLedgerSupplier(e.target.value)} className={inp}>
                <option value="">— Select supplier —</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">From</label><input type="date" value={ledgerStart} onChange={e => setLedgerStart(e.target.value)} className={inp} /></div>
            <div><label className="block text-xs font-medium text-gray-700 mb-1">To</label><input type="date" value={ledgerEnd} onChange={e => setLedgerEnd(e.target.value)} className={inp} /></div>
          </div>

          {!ledgerSupplier ? (
            <div className="bg-white border border-gray-200 rounded-lg p-8 text-center text-sm text-gray-400">Select a supplier to view their ledger.</div>
          ) : ledgerLoading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : (
            <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    <th className="px-3 py-2 text-left font-medium text-gray-500">Date</th>
                    <th className="px-3 py-2 text-left font-medium text-gray-500">Type</th>
                    <th className="px-3 py-2 text-left font-medium text-gray-500">Document #</th>
                    <th className="px-3 py-2 text-left font-medium text-gray-500">Reference</th>
                    <th className="px-3 py-2 text-left font-medium text-gray-500">Description</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">Debit</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">Credit</th>
                    <th className="px-3 py-2 text-right font-medium text-gray-500">Balance</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {ledgerRows.length === 0 ? (
                    <tr><td colSpan={8} className="px-3 py-6 text-center text-gray-400">No transactions in this period.</td></tr>
                  ) : ledgerRows.map((row, i) => (
                    <tr key={i} className="hover:bg-gray-50">
                      <td className="px-3 py-1.5 text-gray-500">{row.transaction_date}</td>
                      <td className="px-3 py-1.5 text-gray-600">{DOC_LABELS[row.document_type] || row.document_type}</td>
                      <td className="px-3 py-1.5 font-mono text-gray-900">{row.document_number}</td>
                      <td className="px-3 py-1.5 text-gray-500">{row.external_ref || '—'}</td>
                      <td className="px-3 py-1.5 text-gray-500 max-w-xs truncate">{row.description || '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono">{row.debit_amount > 0 ? <span className="text-green-700">{fmt(row.debit_amount)}</span> : '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono">{row.credit_amount > 0 ? <span className="text-red-700">{fmt(row.credit_amount)}</span> : '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono font-semibold">{fmt(row.running_balance)}</td>
                    </tr>
                  ))}
                </tbody>
                {ledgerRows.length > 0 && (
                  <tfoot className="bg-gray-50 border-t-2 border-gray-300 font-semibold text-xs">
                    <tr>
                      <td colSpan={5} className="px-3 py-2 text-right text-gray-600">Closing Balance</td>
                      <td colSpan={2} />
                      <td className="px-3 py-2 text-right font-mono">{fmt(ledgerRows[ledgerRows.length - 1]?.running_balance || 0)}</td>
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
