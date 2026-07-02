import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AmountCell } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type Tab = 'aging' | 'ledger'

type CustomerRef = { id: string; registered_name: string }

type AgingRow = {
  customer_id: string; customer_name: string
  current_bal: number; days_1_30: number; days_31_60: number
  days_61_90: number; over_90: number; total_ar: number
}

type InvoiceBalance = {
  id: string; si_number: string; date: string; due_date: string | null
  customer_id: string; customer_name_snapshot: string
  total_amount: number; balance_due: number; days_overdue: number
}

type LedgerRow = {
  transaction_date: string; doc_type: string; doc_number: string
  description: string; debit_amount: number; credit_amount: number
  running_balance: number
}

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const firstOfMonth = () => { const d = new Date(); d.setDate(1); return d.toISOString().split('T')[0] }

const DOC_LABELS: Record<string, string> = { SI: 'Invoice', OR: 'Receipt', CM: 'Credit Memo', DM: 'Debit Memo' }

export default function ARAgingPage() {
  const { companyId } = useAppCtx()
  const [tab, setTab] = useState<Tab>('aging')

  // ── AR Aging state ─────────────────────────────────────────
  const [asOfDate, setAsOfDate] = useState(today())
  const [agingCustomer, setAgingCustomer] = useState('')
  const [agingRows, setAgingRows] = useState<AgingRow[]>([])
  const [agingLoading, setAgingLoading] = useState(false)
  const [expandedCustomer, setExpandedCustomer] = useState<string | null>(null)
  const [customerInvoices, setCustomerInvoices] = useState<InvoiceBalance[]>([])

  // ── Customer Ledger state ──────────────────────────────────
  const [ledgerCustomer, setLedgerCustomer] = useState('')
  const [ledgerStart, setLedgerStart] = useState(firstOfMonth())
  const [ledgerEnd, setLedgerEnd] = useState(today())
  const [ledgerRows, setLedgerRows] = useState<LedgerRow[]>([])
  const [ledgerLoading, setLedgerLoading] = useState(false)

  const [customers, setCustomers] = useState<CustomerRef[]>([])

  useEffect(() => {
    if (!companyId) return
    supabase.from('customers').select('id,registered_name')
      .eq('company_id', companyId).eq('is_active', true).order('registered_name')
      .then(({ data }) => setCustomers(data as CustomerRef[] || []))
  }, [companyId])

  const runAging = useCallback(async () => {
    if (!companyId) return
    setAgingLoading(true); setAgingRows([]); setExpandedCustomer(null); setCustomerInvoices([])
    const asOf = new Date(asOfDate)

    let q = supabase.from('sales_invoices').select('id,si_number,date,due_date,customer_id,customer_name_snapshot,total_amount')
      .eq('company_id', companyId).eq('status', 'posted').lte('date', asOfDate)
    if (agingCustomer) q = q.eq('customer_id', agingCustomer)
    const { data: invoices } = await q

    if (!invoices || invoices.length === 0) { setAgingLoading(false); return }

    const invoiceIds = invoices.map(i => i.id)
    const { data: rlines } = await supabase.from('receipt_lines')
      .select('invoice_id,payment_amount,cwt_amount,receipts!inner(receipt_date,status,company_id)')
      .in('invoice_id', invoiceIds)
      .eq('receipts.company_id', companyId)
      .eq('receipts.status', 'posted')
      .lte('receipts.receipt_date', asOfDate)
    const { data: clines } = await supabase.from('credit_memos')
      .select('invoice_id,total_amount').in('invoice_id', invoiceIds)
      .in('status', ['applied'])
      .lte('cm_date', asOfDate)

    const applied: Record<string, number> = {}
    for (const rl of (rlines as any[]) || []) applied[rl.invoice_id] = (applied[rl.invoice_id] || 0) + Number(rl.payment_amount) + Number(rl.cwt_amount)
    for (const cl of (clines as any[]) || []) applied[cl.invoice_id] = (applied[cl.invoice_id] || 0) + Number(cl.total_amount)

    const balances: InvoiceBalance[] = (invoices as InvoiceBalance[]).map(inv => {
      const paid = applied[inv.id] || 0
      const balance_due = Math.max(0, Number(inv.total_amount) - paid)
      const dueDate = inv.due_date ? new Date(inv.due_date) : null
      const days_overdue = dueDate ? Math.floor((asOf.getTime() - dueDate.getTime()) / 86_400_000) : 0
      return { ...inv, total_amount: Number(inv.total_amount), balance_due, days_overdue }
    }).filter(b => b.balance_due > 0.005)

    // Group by customer
    const byCustomer: Record<string, AgingRow> = {}
    for (const b of balances) {
      if (!byCustomer[b.customer_id]) {
        byCustomer[b.customer_id] = { customer_id: b.customer_id, customer_name: b.customer_name_snapshot, current_bal: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total_ar: 0 }
      }
      const row = byCustomer[b.customer_id]
      const d = b.days_overdue
      if (d <= 0) row.current_bal += b.balance_due
      else if (d <= 30) row.days_1_30 += b.balance_due
      else if (d <= 60) row.days_31_60 += b.balance_due
      else if (d <= 90) row.days_61_90 += b.balance_due
      else row.over_90 += b.balance_due
      row.total_ar += b.balance_due
    }
    setAgingRows(Object.values(byCustomer).sort((a, b) => b.total_ar - a.total_ar))
    setAgingLoading(false)
  }, [companyId, asOfDate, agingCustomer])

  useEffect(() => { if (tab === 'aging' && companyId) runAging() }, [tab, companyId, runAging])

  const expandCustomer = async (customerId: string) => {
    if (expandedCustomer === customerId) { setExpandedCustomer(null); return }
    setExpandedCustomer(customerId)
    const asOf = new Date(asOfDate)
    const { data: invoices } = await supabase.from('sales_invoices')
      .select('id,si_number,date,due_date,customer_id,customer_name_snapshot,total_amount')
      .eq('company_id', companyId!).eq('customer_id', customerId).eq('status', 'posted').lte('date', asOfDate)
    if (!invoices) return
    const invoiceIds = invoices.map(i => i.id)
    const { data: rlines } = await supabase.from('receipt_lines')
      .select('invoice_id,payment_amount,cwt_amount,receipts!inner(receipt_date,status,company_id)')
      .in('invoice_id', invoiceIds)
      .eq('receipts.company_id', companyId!)
      .eq('receipts.status', 'posted')
      .lte('receipts.receipt_date', asOfDate)
    const { data: clines } = await supabase.from('credit_memos')
      .select('invoice_id,total_amount')
      .in('invoice_id', invoiceIds)
      .in('status', ['applied'])
      .lte('cm_date', asOfDate)
    const applied: Record<string, number> = {}
    for (const rl of (rlines as any[]) || []) applied[rl.invoice_id] = (applied[rl.invoice_id] || 0) + Number(rl.payment_amount) + Number(rl.cwt_amount)
    for (const cl of (clines as any[]) || []) applied[cl.invoice_id] = (applied[cl.invoice_id] || 0) + Number(cl.total_amount)
    const results = (invoices as InvoiceBalance[]).map(inv => {
      const paid = applied[inv.id] || 0
      const balance_due = Math.max(0, Number(inv.total_amount) - paid)
      const dueDate = inv.due_date ? new Date(inv.due_date) : null
      const days_overdue = dueDate ? Math.floor((asOf.getTime() - dueDate.getTime()) / 86_400_000) : 0
      return { ...inv, total_amount: Number(inv.total_amount), balance_due, days_overdue }
    }).filter(b => b.balance_due > 0.005)
    setCustomerInvoices(results)
  }

  const runLedger = useCallback(async () => {
    if (!companyId || !ledgerCustomer) return
    setLedgerLoading(true); setLedgerRows([])
    const { data } = await supabase.from('vw_customer_ledger')
      .select('transaction_date,doc_type,doc_number,description,debit_amount,credit_amount,created_at')
      .eq('company_id', companyId).eq('customer_id', ledgerCustomer)
      .gte('transaction_date', ledgerStart).lte('transaction_date', ledgerEnd)
      .order('transaction_date').order('created_at')
    let balance = 0
    const rows: LedgerRow[] = (data || []).map(r => {
      balance += Number(r.debit_amount) - Number(r.credit_amount)
      return { transaction_date: r.transaction_date, doc_type: r.doc_type, doc_number: r.doc_number, description: r.description, debit_amount: Number(r.debit_amount), credit_amount: Number(r.credit_amount), running_balance: balance }
    })
    setLedgerRows(rows)
    setLedgerLoading(false)
  }, [companyId, ledgerCustomer, ledgerStart, ledgerEnd])

  useEffect(() => { if (tab === 'ledger') runLedger() }, [tab, runLedger])

  // ── Aging totals ───────────────────────────────────────────
  const totals = agingRows.reduce((acc, r) => ({ current_bal: acc.current_bal + r.current_bal, days_1_30: acc.days_1_30 + r.days_1_30, days_31_60: acc.days_31_60 + r.days_31_60, days_61_90: acc.days_61_90 + r.days_61_90, over_90: acc.over_90 + r.over_90, total_ar: acc.total_ar + r.total_ar }), { current_bal: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total_ar: 0 })

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        {(['aging', 'ledger'] as Tab[]).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${tab === t ? 'bg-gray-900 text-white' : 'text-gray-600 hover:bg-gray-100'}`}>
            {t === 'aging' ? 'AR Aging' : 'Customer Ledger'}
          </button>
        ))}
      </div>

      {/* ── AR Aging ── */}
      {tab === 'aging' && (
        <div>
          <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
            <div className="flex items-center gap-2">
              <label className="text-xs text-gray-500 whitespace-nowrap">As of Date</label>
              <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)} className={inp} />
            </div>
            <div className="flex items-center gap-2">
              <label className="text-xs text-gray-500">Customer</label>
              <select value={agingCustomer} onChange={e => setAgingCustomer(e.target.value)} className={inp + ' w-56'}>
                <option value="">All Customers</option>
                {customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select>
            </div>
            <button onClick={runAging} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">Run</button>
            {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
          </div>

          {agingLoading ? (
            <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-32" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
          ) : agingRows.length === 0 ? (
            <div className="py-20 text-center">
              <p className="text-sm font-medium text-gray-500">No outstanding balances</p>
              <p className="text-xs text-gray-400 mt-1">No posted invoices with unpaid balances as of {asOfDate}.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    <th className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 min-w-[200px]">Customer</th>
                    <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">Current</th>
                    <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">1–30 Days</th>
                    <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">31–60 Days</th>
                    <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">61–90 Days</th>
                    <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">Over 90</th>
                    <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">Total AR</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {agingRows.map(row => (
                    <>
                      <tr key={row.customer_id} onClick={() => expandCustomer(row.customer_id)}
                        className="hover:bg-gray-50 cursor-pointer transition-colors">
                        <td className="px-4 py-2.5 text-xs font-medium text-gray-900 flex items-center gap-1">
                          <svg className={`h-3 w-3 text-gray-400 transition-transform ${expandedCustomer === row.customer_id ? 'rotate-90' : ''}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M9 18l6-6-6-6" /></svg>
                          {row.customer_name}
                        </td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums text-gray-600">{row.current_bal ? fmt(row.current_bal) : '—'}</td>
                        <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums ${row.days_1_30 ? 'text-amber-700' : 'text-gray-400'}`}>{row.days_1_30 ? fmt(row.days_1_30) : '—'}</td>
                        <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums ${row.days_31_60 ? 'text-orange-700' : 'text-gray-400'}`}>{row.days_31_60 ? fmt(row.days_31_60) : '—'}</td>
                        <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums ${row.days_61_90 ? 'text-red-700' : 'text-gray-400'}`}>{row.days_61_90 ? fmt(row.days_61_90) : '—'}</td>
                        <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold ${row.over_90 ? 'text-red-800' : 'text-gray-400'}`}>{row.over_90 ? fmt(row.over_90) : '—'}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(row.total_ar)}</td>
                      </tr>
                      {expandedCustomer === row.customer_id && (
                        <tr>
                          <td colSpan={7} className="bg-gray-50 border-t border-gray-200">
                            <table className="w-full text-xs">
                              <thead>
                                <tr className="text-gray-400">
                                  <th className="px-8 py-2 text-left font-medium">SI Date</th>
                                  <th className="px-4 py-2 text-left font-medium">SI Number</th>
                                  <th className="px-4 py-2 text-left font-medium">Due Date</th>
                                  <th className="px-4 py-2 text-right font-medium">Original Amount</th>
                                  <th className="px-4 py-2 text-right font-medium">Balance Due</th>
                                  <th className="px-4 py-2 text-right font-medium">Days Overdue</th>
                                </tr>
                              </thead>
                              <tbody>
                                {customerInvoices.map(inv => (
                                  <tr key={inv.id} className="border-t border-gray-200">
                                    <td className="px-8 py-1.5 text-gray-600">{inv.date}</td>
                                    <td className="px-4 py-1.5 font-mono font-semibold text-gray-700">{inv.si_number}</td>
                                    <td className="px-4 py-1.5 text-gray-500">{inv.due_date || '—'}</td>
                                    <td className="px-4 py-1.5 text-right font-mono tabular-nums">{fmt(inv.total_amount)}</td>
                                    <td className="px-4 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(inv.balance_due)}</td>
                                    <td className={`px-4 py-1.5 text-right font-mono tabular-nums ${inv.days_overdue > 90 ? 'text-red-700 font-semibold' : inv.days_overdue > 30 ? 'text-orange-700' : inv.days_overdue > 0 ? 'text-amber-700' : 'text-gray-400'}`}>
                                      {inv.days_overdue > 0 ? `${inv.days_overdue}d` : 'Current'}
                                    </td>
                                  </tr>
                                ))}
                              </tbody>
                            </table>
                          </td>
                        </tr>
                      )}
                    </>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td className="px-4 py-2.5 text-xs font-semibold text-gray-700">TOTAL</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold">{fmt(totals.current_bal)}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-amber-700">{fmt(totals.days_1_30)}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-orange-700">{fmt(totals.days_31_60)}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-red-700">{fmt(totals.days_61_90)}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-red-800">{fmt(totals.over_90)}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold text-gray-900">{fmt(totals.total_ar)}</td>
                  </tr>
                </tfoot>
              </table>
            </div>
          )}
        </div>
      )}

      {/* ── Customer Ledger ── */}
      {tab === 'ledger' && (
        <div>
          <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
            <div className="flex items-center gap-2">
              <label className="text-xs text-gray-500 whitespace-nowrap">Customer <span className="text-red-500">*</span></label>
              <select value={ledgerCustomer} onChange={e => setLedgerCustomer(e.target.value)} className={inp + ' w-56'}>
                <option value="">Select customer…</option>
                {customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select>
            </div>
            <div className="flex items-center gap-2">
              <label className="text-xs text-gray-500">From</label>
              <input type="date" value={ledgerStart} onChange={e => setLedgerStart(e.target.value)} className={inp} />
            </div>
            <div className="flex items-center gap-2">
              <label className="text-xs text-gray-500">To</label>
              <input type="date" value={ledgerEnd} onChange={e => setLedgerEnd(e.target.value)} className={inp} />
            </div>
            <button onClick={runLedger} disabled={!ledgerCustomer} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">Run</button>
          </div>

          {!ledgerCustomer ? (
            <div className="py-20 text-center text-sm text-gray-400">Select a customer to view their ledger.</div>
          ) : ledgerLoading ? (
            <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
          ) : ledgerRows.length === 0 ? (
            <div className="py-20 text-center">
              <p className="text-sm font-medium text-gray-500">No transactions found</p>
              <p className="text-xs text-gray-400 mt-1">No posted transactions for this customer in the selected period.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date','Type','Document No.','Description','Debit','Credit','Balance'].map(h => (
                      <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Debit' || h === 'Credit' || h === 'Balance' ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {ledgerRows.map((r, i) => (
                    <tr key={i} className="hover:bg-gray-50/50">
                      <td className="px-4 py-2 text-xs text-gray-600 whitespace-nowrap">{r.transaction_date}</td>
                      <td className="px-4 py-2">
                        <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase tracking-wide ${r.doc_type === 'SI' ? 'bg-blue-50 text-blue-700' : r.doc_type === 'OR' ? 'bg-green-50 text-green-700' : r.doc_type === 'CM' ? 'bg-amber-50 text-amber-700' : 'bg-red-50 text-red-700'}`}>
                          {r.doc_type}
                        </span>
                      </td>
                      <td className="px-4 py-2 font-mono text-xs font-semibold text-gray-700 whitespace-nowrap">{r.doc_number}</td>
                      <td className="px-4 py-2 text-xs text-gray-500 max-w-[200px] truncate" title={r.description}>{DOC_LABELS[r.doc_type] || r.description}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums">{r.debit_amount ? <span className="text-gray-900">{fmt(r.debit_amount)}</span> : <span className="text-gray-300">—</span>}</td>
                      <td className="px-4 py-2 text-right font-mono text-xs tabular-nums">{r.credit_amount ? <span className="text-green-700">{fmt(r.credit_amount)}</span> : <span className="text-gray-300">—</span>}</td>
                      <td className={`px-4 py-2 text-right font-mono text-xs tabular-nums font-semibold ${r.running_balance >= 0 ? 'text-gray-900' : 'text-red-700'}`}>
                        <AmountCell amount={r.running_balance} />
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-gray-700">CLOSING BALANCE</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold">{fmt(ledgerRows.reduce((s, r) => s + r.debit_amount, 0))}</td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-green-700">{fmt(ledgerRows.reduce((s, r) => s + r.credit_amount, 0))}</td>
                    <td className={`px-4 py-2.5 text-right font-mono text-xs tabular-nums font-bold ${ledgerRows[ledgerRows.length - 1]?.running_balance >= 0 ? 'text-gray-900' : 'text-red-700'}`}>
                      {ledgerRows.length ? fmt(ledgerRows[ledgerRows.length - 1].running_balance) : '—'}
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
